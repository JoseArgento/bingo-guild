"""Bingo de la Guild running in Lua 5.1 (the Lua of WoW) on a small stand-in for the client.

Two or more clients can run side by side: `deliver` carries the addon messages one sent to the others, the
way the GUILD channel would, so the sync is tested end to end.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

lupa = pytest.importorskip("lupa.lua51")

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "BingoDeLaGuild"
TESTS = Path(__file__).resolve().parent


def toc_files():
    lines = (ADDON / "BingoDeLaGuild.toc").read_text(encoding="utf-8").splitlines()
    return [ln.strip().replace("\\", "/") for ln in lines if ln.strip() and not ln.startswith("#")]


class Client:
    def __init__(self, name="Josecito", guild="Los Del Fondo", locale="enUS", saved=None, trial=False):
        self.name = name
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((TESTS / "wow_mock.lua").read_text(encoding="utf-8"))
        self.lua.execute((TESTS / "bingo_mock.lua").read_text(encoding="utf-8"))
        self.m = self.lua.globals().MOCK
        self.m.locale = locale
        self.m.player.name = name
        self.m.trial = trial
        if guild is None:
            self.m.guild = None
        else:
            self.m.guild.name = guild
        if saved is not None:
            self.lua.execute(saved)
        self.ns = self.lua.table()
        loader = self.lua.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")
        for rel in toc_files():
            loader((ADDON / rel).read_text(encoding="utf-8"), f"BingoDeLaGuild/{rel}")("BingoDeLaGuild", self.ns)

    def login(self):
        self.fire("ADDON_LOADED", "BingoDeLaGuild")
        self.fire("PLAYER_LOGIN")
        return self

    def run(self, code):
        return self.lua.eval("function(ns, MOCK) " + code + " end")(self.ns, self.m)

    def fire(self, event, *args):
        self.m.fire(event, *args)

    def timers(self, rounds=3):
        for _ in range(rounds):
            self.m.runTimers()

    def sent(self):
        s = self.m.sent
        return [(s[i].prefix, s[i].text, s[i].chatType) for i in range(1, len(s) + 1)]

    def take_sent(self):
        out = self.sent()
        self.run("MOCK.sent = {}")
        return out

    def chat(self):
        c = self.m.chat
        return [c[i] for i in range(1, len(c) + 1)]

    def warnings(self):
        w = self.m.warnings
        return [w[i] for i in range(1, len(w) + 1)]

    def receive(self, text, sender="Ana-Forever", channel="GUILD", prefix="BingoGuild1"):
        self.fire("CHAT_MSG_ADDON", prefix, text, channel, sender, "", 0, 0, "", 0)

    def card(self):
        c = self.ns.Card()
        return [c[i] for i in range(1, 26)]

    def marks(self):
        return self.ns.Marks()

    def week(self):
        return self.run("return (ns.Week())")

    def guild_cards(self):
        cards = self.ns.GuildCards()
        return {k: v.m for k, v in cards.items()}

    def done(self, goal):
        return self.ns.Done(goal)

    def save(self):
        return self.m.savedVariables("BingoDeLaGuildDB")


def deliver(src: Client, *dests: Client):
    """Carry what src sent on GUILD to the others (and run their timers so replies go out)."""
    src.timers()
    for _prefix, text, chat_type in src.take_sent():
        assert chat_type == "GUILD"
        for d in dests:
            d.receive(text, sender=f"{src.name}-Forever")


def card_message(c: Client, marks: str | None = None, week: str | None = None, pool: int = 1):
    return f"C|{pool}|{week or c.week()}|{marks or '0' * 12 + '1' + '0' * 12}"


@pytest.fixture
def me():
    return Client().login()


# the card ---------------------------------------------------------------------------------------


def test_card_has_24_different_goals_and_a_free_center(me):
    card = me.card()
    assert len(card) == 25
    assert card[12] == "free"
    goals = [g for g in card if g != "free"]
    assert len(set(goals)) == 24
    assert all(me.ns.GOAL[g] is not None for g in goals)


def test_the_whole_guild_draws_the_same_card():
    a, b = Client("Josecito").login(), Client("Ana").login()
    assert a.card() == b.card()
    other = Client("Beto", guild="Otra Guild").login()
    assert other.card() != a.card()


def test_every_week_brings_a_new_card(me):
    first = me.card()
    me.run("MOCK.now = MOCK.resetAt + 60; MOCK.resetAt = MOCK.resetAt + 7 * 86400")
    assert me.card() != first


def test_without_a_guild_the_card_is_yours():
    a, b = Client("Josecito", guild=None).login(), Client("Ana", guild=None).login()
    assert a.card() != b.card()


def test_drawing_a_card_leaves_math_random_alone(me):
    same = me.run(
        """
        math.randomseed(42); local a = math.random()
        math.randomseed(42); ns.Card('g:Prueba-Forever', '123'); local b = math.random()
        return a == b
        """
    )
    assert same
    for p in ADDON.rglob("*.lua"):
        assert "randomseed" not in p.read_text(encoding="utf-8")


def test_the_pool_is_versioned():
    """Changing the goals changes everyone's card: the version must go up with it (and this list too)."""
    ids = re.findall(r'\{ id = "(\w+)"', (ADDON / "Goals.lua").read_text(encoding="utf-8"))
    expected = (TESTS / "pool_v1.txt").read_text(encoding="utf-8").split()
    version = int(re.search(r"POOL_VERSION = (\d+)", (ADDON / "Goals.lua").read_text(encoding="utf-8")).group(1))
    assert version == 1 and ids == expected, "goals changed: bump POOL_VERSION and add tests/pool_v<N>.txt"
    assert len(set(ids)) == len(ids) >= 30


# lines ------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("squares", "lines"),
    [
        ([13], 0),
        ([1, 2, 3, 4, 5, 13], 1),  # first row
        ([3, 8, 13, 18, 23], 1),  # middle column, through the free square
        ([1, 7, 13, 19, 25], 1),  # diagonal
        ([5, 9, 13, 17, 21], 1),  # the other diagonal
        ([11, 12, 13, 14, 15, 3, 8, 18, 23], 2),  # middle row and middle column
        (list(range(1, 26)), 12),
    ],
)
def test_lines(me, squares, lines):
    marks = "".join("1" if i in squares else "0" for i in range(1, 26))
    assert me.lua.eval("function(ns, m) return (ns.Lines(m)) end")(me.ns, marks) == lines


# goals that mark themselves -----------------------------------------------------------------------


def test_deaths_levels_and_quests_count(me):
    for _ in range(3):
        me.fire("PLAYER_DEAD")
    me.fire("PLAYER_LEVEL_UP", 11)
    for _ in range(10):
        me.fire("QUEST_TURNED_IN", 176, 0, 0)
    assert me.done("die1") and me.done("die3")
    assert me.done("lvl1") and not me.done("lvl3")
    assert me.done("q10") and not me.done("q25")


def test_zones_and_days_count_once_each(me):
    for zone in ["Elwynn Forest", "Elwynn Forest", "Westfall", "Duskwood", "Redridge Mountains"]:
        me.run(f"MOCK.where.zone = '{zone}'")
        me.fire("ZONE_CHANGED_NEW_AREA")
    assert not me.done("zone5")  # Elwynn twice: 4 zones
    me.run("MOCK.where.zone = 'Stormwind City'")
    me.fire("ZONE_CHANGED_NEW_AREA")
    assert me.done("zone5")
    me.run("MOCK.resetAt = MOCK.now + 5 * 86400")  # three days in the same week
    me.m.tick()
    assert me.ns.ThisWeek().count.day == 1
    me.run("MOCK.now = MOCK.now + 86400")
    me.m.tick()
    me.run("MOCK.now = MOCK.now + 86400")
    me.m.tick()
    assert me.done("days3")


def test_bosses_only_when_killed(me):
    me.fire("ENCOUNTER_END", 1, "Hogger", 1, 5, 0)
    assert not me.done("boss")
    me.fire("ENCOUNTER_END", 1, "Hogger", 1, 5, 1)
    assert me.done("boss")


def test_screenshot_counts_only_in_a_group(me):
    me.fire("SCREENSHOT_SUCCEEDED")
    assert not me.done("shot")
    me.run("MOCK.inGroup = true")
    me.fire("SCREENSHOT_SUCCEEDED")
    assert me.done("shot")


def test_rare_targets(me):
    me.run("MOCK.target = { name = 'Gnoll', classification = 'normal' }")
    me.fire("PLAYER_TARGET_CHANGED")
    assert not me.done("rare")
    me.run("MOCK.target = { name = 'Mother Fang', classification = 'rare' }")
    me.fire("PLAYER_TARGET_CHANGED")
    assert me.done("rare")


def test_secret_values_are_left_alone(me):
    me.run("MOCK.target = { name = 'X', classification = 'rare' }; MOCK.secret['rare'] = true")
    me.fire("PLAYER_TARGET_CHANGED")
    assert not me.done("rare")


def test_flights_need_the_taxi(me):
    me.fire("PLAYER_CONTROL_LOST")
    me.timers()
    assert not me.done("taxi")
    me.run("MOCK.onTaxi = true")
    me.fire("PLAYER_CONTROL_LOST")
    me.timers()
    assert me.done("taxi")


def test_grouping_with_a_guildmate(me):
    me.run("MOCK.group = { party1 = 'Rando' }")
    me.fire("GROUP_ROSTER_UPDATE")
    assert not me.done("gparty")
    me.run("MOCK.group = { party1 = 'Rando', party2 = 'Ana' }; MOCK.guildmates = { party2 = true }")
    me.fire("GROUP_ROSTER_UPDATE")
    assert me.done("gparty")


def test_blue_loot(me):
    me.run("MOCK.items[2589] = 2; MOCK.items[6070] = 3")
    me.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:2589::::::::10|h[Linen Cloth]|h|r")
    assert not me.done("blue")
    me.fire("CHAT_MSG_LOOT", "Ana receives loot: |cff0070dd|Hitem:6070::::::::10|h[Wolfshead Helm]|h|r")
    assert not me.done("blue")  # someone else's
    me.fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:6070::::::::10|h[Wolfshead Helm]|h|r")
    assert me.done("blue")


def test_duel_mail_and_auction_house(me):
    for event in ["DUEL_FINISHED", "MAIL_SEND_SUCCESS", "AUCTION_HOUSE_SHOW"]:
        me.fire(event)
    assert me.done("duel") and me.done("mail") and me.done("ah")


# clicking ---------------------------------------------------------------------------------------


def test_click_marks_and_unmarks(me):
    assert me.ns.Toggle("fall")
    assert me.done("fall")
    assert me.ns.Toggle("fall")
    assert not me.done("fall")


def test_a_goal_that_counted_itself_stays_marked(me):
    me.fire("PLAYER_DEAD")
    assert not me.ns.Toggle("die1")
    assert me.done("die1")


def test_bingo_is_called_once_per_new_line(me):
    card = me.card()
    for g in card[0:4]:
        me.ns.Toggle(g) if not me.done(g) else None
    assert me.warnings() == []
    if not me.done(card[4]):
        me.ns.Toggle(card[4])
    assert len(me.warnings()) == 1
    assert me.ns.ThisWeek().lines == 1
    # another mark that makes no new line: no second call
    if not me.done(card[5]):
        me.ns.Toggle(card[5])
    assert len(me.warnings()) == 1


def mark_row(c: Client, row: int):
    for g in c.card()[row * 5 : row * 5 + 5]:
        if g != "free" and not c.done(g):
            c.ns.Toggle(g)


# the guild --------------------------------------------------------------------------------------


def test_two_players_see_each_others_cards():
    jose, ana = Client("Josecito").login(), Client("Ana").login()
    mark_row(jose, 0)
    deliver(jose, ana)
    deliver(ana, jose)
    assert ana.guild_cards()["Josecito"] == jose.marks()
    assert jose.guild_cards()["Ana"] == ana.marks()
    assert any("Josecito called BINGO" in line for line in ana.chat())


def test_a_newcomer_gets_the_cards_by_asking():
    jose = Client("Josecito").login()
    mark_row(jose, 1)
    jose.timers()
    jose.take_sent()
    ana = Client("Ana").login()
    ana.timers()
    sent = ana.take_sent()
    assert any(t.startswith("Q|1|") for _, t, _ in sent)
    for _, text, _ in sent:
        jose.receive(text, sender="Ana-Forever")
    deliver(jose, ana)
    assert ana.guild_cards()["Josecito"] == jose.marks()


def test_many_questions_get_one_answer(me):
    me.timers()
    me.take_sent()
    for who in ["Ana", "Beto", "Caro"]:
        me.receive(f"Q|1|{me.week()}", sender=f"{who}-Forever")
    me.timers()
    answers = [t for _, t, _ in me.take_sent() if t.startswith("C|")]
    assert len(answers) == 1


def test_marks_go_out_a_moment_after_a_click(me):
    me.timers()
    me.take_sent()
    me.ns.Toggle("fall")
    me.ns.Toggle("guard")
    assert me.sent() == []  # waits a little, so several clicks make one message
    me.timers()
    sent = me.take_sent()
    assert len(sent) == 1
    assert sent[0] == ("BingoGuild1", f"C|1|{me.week()}|{me.marks()}", "GUILD")


@pytest.mark.parametrize(
    "kwargs",
    [
        {"channel": "PARTY"},
        {"channel": "WHISPER"},
        {"prefix": "OtroAddon"},
        {"text": "C|1|WEEK|0101"},  # too few marks
        {"text": "C|1|WEEK|" + "0" * 25},  # the free square unmarked
        {"text": "C|1|WEEK|" + "2" * 25},
        {"text": "C|1|WEEK|" + "1" * 25 + "|os.exit()"},
        {"text": "loadstring('x')()"},
        {"text": "C|1|WEEK|" + "1" * 200},
        {"text": "C|1|999|" + "1" * 25},  # another week
        {"sender": "Josecito-Forever"},  # my own message coming back
    ],
)
def test_bad_messages_are_ignored(me, kwargs):
    text = kwargs.pop("text", "C|1|WEEK|" + "1" * 25).replace("WEEK", me.week())
    me.receive(text, **kwargs)
    assert me.guild_cards() == {}


def test_secret_senders_are_ignored(me):
    me.run("MOCK.secret['Ana-Forever'] = true")
    me.receive(card_message(me))
    assert me.guild_cards() == {}


def test_another_version_is_ignored_and_said_once(me):
    me.receive(card_message(me, pool=2))
    me.receive(card_message(me, pool=2))
    assert me.guild_cards() == {}
    assert sum("another version" in line for line in me.chat()) == 1


def test_one_sender_cannot_flood(me):
    for i in range(10):
        marks = "1" * (i + 1) + "0" * (24 - i)
        marks = marks[:12] + "1" + marks[13:]
        me.receive(card_message(me, marks))
    stored = me.guild_cards()["Ana"]
    assert stored == ("1" * 5 + "0" * 7 + "1" + "0" * 12)  # the 5th message; the rest were dropped
    me.run("MOCK.now = MOCK.now + 11")
    me.receive(card_message(me, "1" * 25))
    assert me.guild_cards()["Ana"] == "1" * 25


def test_at_most_a_guilds_worth_of_cards(me):
    for i in range(1005):
        me.receive(card_message(me), sender=f"P{i}-Forever")
    assert len(me.guild_cards()) == 1000


def test_trial_accounts_listen_but_do_not_send():
    t = Client("Prueba", trial=True).login()
    t.ns.Toggle("fall")
    t.timers()
    assert t.sent() == []
    t.receive(card_message(t))
    assert "Ana" in t.guild_cards()
    t.run("ns.UI.Toggle()")
    assert "Trial accounts" in t.run("return ns.UI.frame.note:GetText()")


def test_no_guild_no_messages():
    c = Client("Solo", guild=None).login()
    c.ns.Toggle("fall")
    c.timers()
    assert c.sent() == []
    c.run("ns.UI.Toggle()")
    assert "not in a guild" in c.run("return ns.UI.frame.note:GetText()")


def test_a_throttled_send_is_tried_again(me):
    me.timers()
    me.take_sent()
    me.run("MOCK.sendResult = 3")  # AddonMessageThrottle
    me.ns.Toggle("fall")
    me.m.runTimers()  # the share goes out and is throttled
    assert me.sent() == []
    me.run("MOCK.sendResult = 0")
    me.timers()
    assert len(me.take_sent()) == 1


def test_during_a_chat_lockdown_it_waits(me):
    me.timers()
    me.take_sent()
    me.run("MOCK.lockdown = true")
    me.ns.Toggle("fall")
    me.m.runTimers()
    assert me.sent() == []
    me.run("MOCK.lockdown = false")
    me.timers()
    assert len(me.take_sent()) == 1


# weeks, saving ----------------------------------------------------------------------------------


def test_the_weekly_reset_starts_a_clean_card(me):
    me.fire("PLAYER_DEAD")
    me.ns.Toggle("fall")
    old_week = me.week()
    me.timers()
    me.take_sent()
    me.run("MOCK.now = MOCK.resetAt + 60; MOCK.resetAt = MOCK.resetAt + 7 * 86400")
    me.m.tick()
    assert me.week() != old_week
    assert not me.done("die1") and not me.done("fall")
    me.timers()
    assert any(t.startswith(f"Q|1|{me.week()}") for _, t, _ in me.take_sent())


def test_saved_and_loaded():
    a = Client().login()
    a.fire("PLAYER_DEAD")
    a.ns.Toggle("fall")
    a.receive(card_message(a))
    marks = a.marks()
    b = Client(saved=a.save()).login()
    assert b.marks() == marks
    assert b.done("die1") and b.done("fall")
    assert b.guild_cards() == {"Ana": "0" * 12 + "1" + "0" * 12}


def test_old_weeks_are_dropped():
    a = Client().login()
    a.ns.Toggle("fall")
    a.receive(card_message(a))
    saved = a.save()
    b = Client(saved=saved)
    b.run("MOCK.now = MOCK.now + 40 * 86400; MOCK.resetAt = MOCK.now + 3600")
    b.login()
    assert len(list(b.lua.globals().BingoDeLaGuildDB.chars["Josecito-Forever"].weeks.keys())) == 1  # just the new one
    assert len(list(b.lua.globals().BingoDeLaGuildDB.guilds["g:Los Del Fondo-Forever"].keys())) <= 1


# the window -------------------------------------------------------------------------------------


def test_the_window(me):
    me.fire("PLAYER_DEAD")
    me.receive(card_message(me, "1" * 25))
    me.lua.globals().SlashCmdList.BINGODELAGUILD("")
    ui = me.ns.UI
    assert ui.frame.IsShown(ui.frame)
    card = me.card()
    cells = [ui.cells[i] for i in range(1, 26)]
    assert cells[12].text.GetText(cells[12].text) == "Free square"
    for i, cell in enumerate(cells):
        if card[i] != "free":
            assert cell.text.GetText(cell.text) == me.ns.GoalText(me.ns.GOAL[card[i]])
    assert "Ana" in ui.rows[1].GetText(ui.rows[1])
    assert "BingoDeLaGuildFrame" in list(me.lua.globals().UISpecialFrames.values())


def test_clicking_a_square_and_its_tooltip(me):
    me.receive(card_message(me, "1" * 25))
    me.run("ns.UI.Toggle()")
    card = me.card()
    i = next(i for i, g in enumerate(card) if g != "free" and me.ns.GOAL[g].count is None)
    cell = me.ns.UI.cells[i + 1]
    cell._scripts.OnClick(cell)
    assert me.done(card[i])
    cell._scripts.OnEnter(cell)
    lines = me.run("return table.concat(GameTooltip.lines or {}, '\\n')")
    assert "Also done by: Ana" in lines


def test_announce_only_on_click(me):
    me.run("ns.UI.Toggle()")
    mark_row(me, 2)
    assert list(me.m.chatSent.values()) == []
    button = me.ns.UI.frame.announce
    assert button.IsShown(button)
    button._scripts.OnClick(button)
    sent = list(me.m.chatSent.values())
    assert len(sent) == 1 and sent[0].chatType == "GUILD"


def test_spanish():
    c = Client(locale="esES").login()
    assert c.ns.GoalText(c.ns.GOAL["fall"]) == "Morir de una caída"
    c.receive(card_message(c, "1" * 25))
    assert any("Ana cantó BINGO" in line for line in c.chat())


def test_slash_sync_and_compartment(me):
    me.timers()
    me.take_sent()
    me.lua.globals().SlashCmdList.BINGODELAGUILD("sync")
    assert any(t.startswith("Q|") for _, t, _ in me.take_sent())
    g = me.lua.globals()
    g.BingoDeLaGuild_OnAddonCompartmentClick()
    assert me.ns.UI.frame.IsShown(me.ns.UI.frame)
    g.BingoDeLaGuild_OnAddonCompartmentEnter(None, me.ns.UI.frame)
    g.BingoDeLaGuild_OnAddonCompartmentLeave()
