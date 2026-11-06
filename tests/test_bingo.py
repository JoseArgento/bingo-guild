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
    return [ln.strip().replace("\\", "/") for ln in lines if ln.strip() and not ln.startswith("#") and ln.strip().endswith(".lua")]


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


def card_message(c: Client, marks: str | None = None, week: str | None = None, pool: int = 3, key: str | None = None):
    key = key or c.ns.CardKey()
    return f"C|{pool}|{week or c.week()}|{key}|{marks or '0' * 12 + '1' + '0' * 12}"


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
    expected = (TESTS / "pool_v3.txt").read_text(encoding="utf-8").split()
    version = int(re.search(r"POOL_VERSION = (\d+)", (ADDON / "Goals.lua").read_text(encoding="utf-8")).group(1))
    assert version == 3 and ids == expected, "goals changed: bump POOL_VERSION and add tests/pool_v<N>.txt"
    # the previous pool stays on disk so an old client's card can be reasoned about
    assert (TESTS / "pool_v2.txt").exists()
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
        me.fire("PLAYER_DEAD")  # Forever fires it twice per death (beta report)
        me.run("MOCK.gametime = MOCK.gametime + 60")
    me.fire("PLAYER_LEVEL_UP", 11)
    for _ in range(10):
        me.fire("QUEST_TURNED_IN", 176, 0, 0)
    assert me.ns.ThisWeek().count.die == 3
    assert me.done("die1") and me.done("die3")
    assert me.done("lvl1") and not me.done("lvl3")
    assert me.done("q10") and not me.done("q25")


def test_zones_and_days_count_once_each(me):
    for zone in ["Elwynn Forest", "Elwynn Forest", "Westfall", "Duskwood", "Redridge Mountains"]:
        me.run(f"MOCK.where.zone = '{zone}'")
        me.fire("ZONE_CHANGED_NEW_AREA")
        me.timers()
    assert not me.done("zone5")  # Elwynn twice: 4 zones
    me.run("MOCK.where.zone = 'Stormwind City'")
    me.fire("ZONE_CHANGED_NEW_AREA")
    assert not me.done("zone5")  # read a moment later, not right away
    me.timers()
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


def test_joining_a_guild_does_not_call_a_false_bingo():
    c = Client("Nuevo", guild=None).login()
    for g in ["fall", "guard", "lost", "dance", "fishjunk", "helplow", "five", "photo", "ghost", "bags"]:
        c.ns.Toggle(g)
    before = len(c.warnings())
    c.run("MOCK.guild = { name = 'Los Del Fondo', realm = 'Forever' }")
    c.fire("PLAYER_GUILD_UPDATE")
    c.ns.Toggle("escort")  # any change on the new card
    assert len(c.warnings()) == before  # the first change on the guild's card never calls bingo
    assert c.ns.ThisWeek().linesCard.startswith("g:")


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
    assert any(t.startswith("Q|3|") for _, t, _ in sent)
    for _, text, _ in sent:
        jose.receive(text, sender="Ana-Forever")
    deliver(jose, ana)
    assert ana.guild_cards()["Josecito"] == jose.marks()


def test_many_questions_get_one_answer(me):
    me.timers()
    me.take_sent()
    for who in ["Ana", "Beto", "Caro"]:
        me.receive(f"Q|3|{me.week()}", sender=f"{who}-Forever")
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
    assert sent[0] == ("BingoGuild1", f"C|3|{me.week()}|{me.ns.CardKey()}|{me.marks()}", "GUILD")


@pytest.mark.parametrize(
    "kwargs",
    [
        {"channel": "PARTY"},
        {"channel": "WHISPER"},
        {"prefix": "OtroAddon"},
        {"text": "C|3|WEEK|KEY|0101"},  # too few marks
        {"text": "C|3|WEEK|KEY|" + "0" * 25},  # the free square unmarked
        {"text": "C|3|WEEK|KEY|" + "2" * 25},
        {"text": "C|3|WEEK|KEY|" + "1" * 25 + "|os.exit()"},
        {"text": "C|3|WEEK|zzzzzz|" + "1" * 25},  # not a card name
        {"text": "C|3|WEEK|" + "1" * 25},  # no card name (version 1 style)
        {"text": "loadstring('x')()"},
        {"text": "C|3|WEEK|KEY|" + "1" * 200},
        {"text": "C|3|999|KEY|" + "1" * 25},  # another week
        {"sender": "Josecito-Forever"},  # my own message coming back
    ],
)
def test_bad_messages_are_ignored(me, kwargs):
    text = kwargs.pop("text", "C|3|WEEK|KEY|" + "1" * 25).replace("WEEK", me.week()).replace("KEY", me.ns.CardKey())
    me.receive(text, **kwargs)
    assert me.guild_cards() == {}


def test_secret_senders_are_ignored(me):
    me.run("MOCK.secret['Ana-Forever'] = true")
    me.receive(card_message(me))
    assert me.guild_cards() == {}


def test_another_version_is_ignored_and_said_once(me):
    me.receive(card_message(me, pool=1))
    me.receive(card_message(me, pool=1))
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
    # with nobody to list, the note sits right under the heading and the empty list stays hidden
    assert c.run("return ns.UI.frame.note._points[1][2] == ns.UI.frame.guildRule")
    assert not c.run("return ns.UI.frame.guild.box:IsShown()")


def test_with_guildmates_the_list_shows_and_the_note_moves_under_it():
    me = Client().login()
    me.receive(card_message(me, "1" * 25))
    me.run("ns.UI.Toggle()")
    assert me.run("return ns.UI.frame.guild.box:IsShown()")
    assert me.run("return ns.UI.frame.note._points[1][2] == ns.UI.frame.guild.box")


def test_one_point_is_singular():
    me = Client().login()
    me.receive(card_message(me, "0" * 12 + "1" + "0" * 12))  # Ana: only the free square
    me.run("ns.UI.Toggle(); ns.UI.frame:SelectTab('liga')")
    rows = me.run("local t = {} for _, r in ipairs(ns.UI.frame.leagueList.box.data or {}) do t[#t+1] = r.right end return table.concat(t, '|')")
    assert "1 pt" in rows and "1 pts" not in rows


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
    assert any(t.startswith(f"Q|3|{me.week()}") for _, t, _ in me.take_sent())


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
    rows = ui.frame.guild.box.rows
    assert "Ana" in rows[1].name.GetText(rows[1].name) and rows[1].count.GetText(rows[1].count) == "25 of 25"
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


# officers' cards (#28) ---------------------------------------------------------------------------


def officer(name="Ofi"):
    c = Client(name).login()
    c.run("MOCK.officer = true")
    return c


def publish(c, goals):
    for g in goals:
        c.lua.globals().SlashCmdList.BINGODELAGUILD("meta " + g)
    c.lua.globals().SlashCmdList.BINGODELAGUILD("publicar")


def test_only_officers_publish(me):
    me.lua.globals().SlashCmdList.BINGODELAGUILD("meta Bailar en Ventormenta")
    assert list(me.ns.Drafts().values()) == []
    assert not me.ns.Publish()
    assert any("Only officers" in line for line in me.chat())


def test_an_officers_goals_go_on_everyones_card():
    ofi, ana = officer(), Client("Ana").login()
    for c in (ofi, ana):
        c.timers()
        c.take_sent()
    before = ana.ns.CardKey()
    publish(ofi, ["Bailar en Ventormenta", "Pescar en Forjaz"])
    card = ofi.card()
    assert {"c1", "c2"} <= set(card) and card[12] == "free"
    assert ofi.ns.GoalText(ofi.ns.Goal("c1")) == "Bailar en Ventormenta"  # as typed, not lowercased
    deliver(ofi, ana)
    assert ana.card() == card
    assert ana.ns.CardKey() == ofi.ns.CardKey() != before
    assert any("Ofi published this week's guild card" in line for line in ana.chat())


def test_a_card_from_someone_who_is_not_an_officer_is_ignored():
    fake, me = Client("Ana").login(), Client().login()
    fake.run("MOCK.officer = true")  # thinks so, but the roster says rank 2
    publish(fake, ["Darme todo tu oro"])
    deliver(fake, me)
    assert "c1" not in me.card()


def test_unknown_senders_ask_for_the_roster(me):
    week = me.week()
    me.receive(f"K|3|{week}|123|1", sender="Nadie-Forever")
    assert me.m.rosterRequests >= 1
    assert me.ns.OfficerCard() is None


def test_half_a_card_is_not_used(me):
    week = me.week()
    me.receive(f"K|3|{week}|123|2", sender="Ofi-Forever")
    me.receive(f"G|3|{week}|123|1|Una sola", sender="Ofi-Forever")
    assert me.ns.OfficerCard() is None
    me.receive(f"G|3|{week}|123|2|La otra", sender="Ofi-Forever")
    card = me.ns.OfficerCard()
    assert list(card.goals.values()) == ["Una sola", "La otra"]


@pytest.mark.parametrize("count", ["0", "25", "x"])
def test_bad_card_sizes(me, count):
    me.receive(f"K|3|{me.week()}|123|{count}", sender="Ofi-Forever")
    me.receive(f"G|3|{me.week()}|123|1|Algo", sender="Ofi-Forever")
    assert me.ns.OfficerCard() is None


def test_an_older_card_does_not_replace_a_newer_one(me):
    w = me.week()
    for ver, text in [("200", "Nueva"), ("100", "Vieja")]:
        me.receive(f"K|3|{w}|{ver}|1", sender="Lider-Forever")
        me.receive(f"G|3|{w}|{ver}|1|{text}", sender="Lider-Forever")
    assert list(me.ns.OfficerCard().goals.values()) == ["Nueva"]


def test_goal_text_is_cleaned(me):
    clean = me.ns.CleanGoal
    assert clean("hola\nchau") == "hola chau"
    assert clean("|cffff0000rojo|r") == "cffff0000rojor"
    long = clean("ñ" * 40)  # 80 bytes: cut at 50 without breaking a letter
    assert long == "ñ" * 25
    assert clean("   ") is None


def test_marks_on_another_card_are_not_compared():
    me = Client().login()
    me.receive(card_message(me, "1" * 25, key="abcdef"))
    assert me.guild_cards()["Ana"] == "1" * 25  # kept...
    assert dict(me.ns.SameCard().items()) == {}  # ...but not compared with yours
    me.run("ns.UI.Toggle()")
    assert len(me.ns.UI.frame.guild.box.rows) == 0


def test_a_late_player_gets_the_officers_card():
    ofi = officer()
    publish(ofi, ["Bailar en Ventormenta"])
    ofi.timers()
    ofi.take_sent()
    late = Client("Ana").login()
    late.timers()
    for _, text, _ in late.take_sent():
        ofi.receive(text, sender="Ana-Forever")
    deliver(ofi, late)
    assert "c1" in late.card()


def test_officer_buttons_only_for_officers():
    for c, shown in [(Client().login(), False), (officer(), True)]:
        c.run("ns.UI.Toggle()")
        f = c.ns.UI.frame
        assert bool(f.publish.IsShown(f.publish)) is shown
        assert bool(f.addGoal.IsShown(f.addGoal)) is shown


# league ------------------------------------------------------------------------------------------


def test_the_league_adds_up_the_weeks():
    me = Client().login()
    mark_row(me, 0)  # the first row: 5 squares (plus the free one in the middle) and one line
    me.receive(card_message(me, "1" * 25))  # Ana: 25 squares, 12 lines
    me.run("MOCK.now = MOCK.resetAt + 60")
    me.m.tick()
    me.receive(card_message(me, "0" * 12 + "1" + "0" * 12))  # Ana's new week: just the free square
    league = me.ns.League()
    table = {league[i].name: (league[i].points, league[i].weeks) for i in range(1, len(league) + 1)}
    assert table["Ana"] == (25 + 5 * 12 + 1, 2)
    assert table["Josecito"] == (6 + 5, 1)  # last week: a row and the free square, one line; nothing this week yet
    assert league[1].name == "Ana"


def test_new_week_is_announced(me):
    me.run("MOCK.now = MOCK.resetAt + 60")
    me.m.tick()
    assert any("New week, new card" in line for line in me.chat())


# pool 3: Forever is live ------------------------------------------------------------------------


def test_a_legacy_point_marks_itself(me):
    me.run("MOCK.legacyPoints[9001] = 0")
    me.fire("ACHIEVEMENT_EARNED", 9001)
    assert not me.done("legacy")
    me.run("MOCK.legacyPoints[9002] = 1")
    me.fire("ACHIEVEMENT_EARNED", 9002)
    assert me.done("legacy")


def test_a_skyborne_at_ten(me):
    me.fire("PLAYER_LEVEL_UP", 10)
    assert not me.done("sky10")  # a human
    me.run("MOCK.player.race = 'Skyborne'")
    me.fire("PLAYER_LEVEL_UP", 9)
    assert not me.done("sky10")
    me.fire("PLAYER_LEVEL_UP", 10)
    assert me.done("sky10")


def test_the_new_dungeons_mark_themselves_by_name(me):
    me.run("MOCK.instance = { name = 'Hall of Thanes', type = 'party' }")
    me.fire("PLAYER_ENTERING_WORLD")
    assert me.done("dg_thanes") and me.done("newdungeon") and not me.done("dg_dalaran")
    me.run("MOCK.instance = { name = 'Deadmines', type = 'party' }")  # not a new one
    me.fire("ZONE_CHANGED_NEW_AREA")
    me.timers()
    assert me.ns.Progress(me.ns.Goal("newdungeon3")) == 1
    for name in ["City of Dalaran", "Blackmaw Hold", "Hall of Thanes"]:
        me.run(f"MOCK.instance = {{ name = '{name}', type = 'party' }}")
        me.fire("ZONE_CHANGED_NEW_AREA")
        me.timers()
    assert me.done("newdungeon3") and me.done("dg_dalaran")
    me.run("ns.UI.Toggle()")
    cell = [c for c in me.ns.UI.cells.values() if c.goalID == "dg_thanes"]
    if cell:  # it is on this week's card: the tooltip says it marks itself
        cell[0]._scripts.OnEnter(cell[0])
        assert any("Marks itself" in line for line in me.lua.globals().GameTooltip.lines.values())


def test_a_raid_or_the_open_world_is_not_a_new_dungeon(me):
    me.run("MOCK.instance = { name = 'Hall of Thanes', type = 'raid' }")
    me.fire("PLAYER_ENTERING_WORLD")
    assert not me.done("dg_thanes")


# suggestions (#11) ------------------------------------------------------------------------------


def suggestions(c):
    s = c.ns.Suggestions()
    return [(s[i].by, s[i].text) for i in range(1, len(s) + 1)]


def test_a_suggestion_reaches_the_officers_only():
    ana, ofi, me = Client("Ana").login(), officer(), Client().login()
    for c in (ana, ofi, me):
        c.timers()
        c.take_sent()
    ana.lua.globals().SlashCmdList.BINGODELAGUILD("sugerir Bailar con un Murloc")
    sent = ana.take_sent()
    assert sent == [("BingoGuild1", f"S|3|{ana.week()}|Bailar con un Murloc", "GUILD")]
    assert any("Suggestion sent" in line for line in ana.chat())
    for c in (ofi, me):
        c.receive(sent[0][1], sender="Ana-Forever")
    assert suggestions(ofi) == [("Ana", "Bailar con un Murloc")]
    assert suggestions(me) == []  # not an officer: dropped
    assert "suggest" not in me.save() or '"Ana"' not in me.save()


def test_suggestions_are_deduped_capped_and_rate_limited():
    ofi = officer()
    w = ofi.week()
    for _ in range(3):
        ofi.receive(f"S|3|{w}|Lo mismo", sender="Ana-Forever")
    assert suggestions(ofi) == [("Ana", "Lo mismo")]
    ofi.receive(f"S|3|{w}|Lo mismo", sender="Beto-Forever")  # another sender: its own
    assert len(suggestions(ofi)) == 2
    for i in range(10):  # more than 5 in 10 seconds from one sender: the rest wait
        ofi.receive(f"S|3|{w}|Idea {i}", sender="Caro-Forever")
    assert len(suggestions(ofi)) == 2 + 5
    ofi.run("MOCK.now = MOCK.now + 11")
    n = 0
    while len(suggestions(ofi)) < 50:
        ofi.receive(f"S|3|{w}|Otra {n}", sender=f"P{n % 40}-Forever")
        n += 1
        if n % 5 == 0:
            ofi.run("MOCK.now = MOCK.now + 11")
    ofi.run("MOCK.now = MOCK.now + 11")
    ofi.receive(f"S|3|{w}|Una de más", sender="Zeta-Forever")
    assert len(suggestions(ofi)) == 50


def test_bad_suggestions_are_ignored():
    ofi = officer()
    w = ofi.week()
    ofi.receive(f"S|3|{w}|", sender="Ana-Forever")
    ofi.receive(f"S|3|{w}|   ", sender="Ana-Forever")
    ofi.receive(f"S|3|{int(w) - 604800}|Vieja", sender="Ana-Forever")
    ofi.receive(f"S|2|{w}|Otra versión", sender="Ana-Forever")
    assert suggestions(ofi) == []
    ofi.receive(f"S|3|{w}|con |cffff0000color|r", sender="Ana-Forever")
    assert suggestions(ofi) == [("Ana", "con cffff0000colorr")]


def test_an_officer_adds_or_drops_a_suggestion():
    ofi = officer()
    w = ofi.week()
    ofi.receive(f"S|3|{w}|Primera", sender="Ana-Forever")
    ofi.receive(f"S|3|{w}|Segunda", sender="Beto-Forever")
    ofi.run("ns.UI.Toggle()")
    f = ofi.ns.UI.frame
    assert f.review.GetText(f.review) == "Suggestions (2)" and f.review.IsShown(f.review)
    f.review._scripts.OnClick(f.review)
    popups = ofi.m.popups
    assert popups[len(popups)].text == "Ana suggests: Primera"
    ofi.lua.globals().StaticPopupDialogs.BINGODELAGUILD_REVIEW.OnAccept()
    assert list(ofi.ns.Drafts().values()) == ["Primera"] and suggestions(ofi) == [("Beto", "Segunda")]
    ofi.lua.globals().StaticPopupDialogs.BINGODELAGUILD_REVIEW.OnCancel(None, None, "clicked")
    assert suggestions(ofi) == [] and list(ofi.ns.Drafts().values()) == ["Primera"]
    assert f.review.GetText(f.review) == "Suggestions (0)"


def test_trial_accounts_cannot_suggest():
    c = Client(trial=True).login()
    c.take_sent()
    c.lua.globals().SlashCmdList.BINGODELAGUILD("sugerir Algo")
    assert c.take_sent() == []
    assert any("Trial accounts" in line for line in c.chat())


def test_the_suggest_button_is_for_members_not_officers():
    for c, shown in [(Client().login(), True), (officer(), False), (Client(guild=None).login(), False)]:
        c.run("ns.UI.Toggle()")
        f = c.ns.UI.frame
        assert bool(f.suggest.IsShown(f.suggest)) is shown


# export / import of the goal list -----------------------------------------------------------------


def test_export_and_import_round_trip():
    ofi = officer()
    assert ofi.ns.ExportGoals() is None
    publish_goals = ["Bailar en Ventormenta", "Pescar en Forjaz", "Con ñandú"]
    for g in publish_goals:
        ofi.lua.globals().SlashCmdList.BINGODELAGUILD("meta " + g)
    text = ofi.ns.ExportGoals()
    assert text == "BINGO1:\nBailar en Ventormenta\nPescar en Forjaz\nCon ñandú"
    other = officer("Lider")
    assert other.ns.ImportGoals(text) == 3
    assert list(other.ns.Drafts().values()) == publish_goals
    assert other.ns.ImportGoals("hola\nchau") is None  # not an export: drafts untouched
    assert list(other.ns.Drafts().values()) == publish_goals


def test_import_cleans_and_caps():
    ofi = officer()
    lines = ["BINGO1:  "] + [f"meta |{i}| " + "x" * 80 for i in range(30)] + ["", "   "]
    n = ofi.ns.ImportGoals("\r\n".join(lines))
    assert n == 24
    drafts = list(ofi.ns.Drafts().values())
    assert len(drafts) == 24 and all("|" not in d and len(d.encode()) <= 50 for d in drafts)
    assert drafts[0].startswith("meta 0 xxx")


def test_the_exchange_window(me):
    ofi = officer()
    ofi.lua.globals().SlashCmdList.BINGODELAGUILD("meta Una")
    ofi.lua.globals().SlashCmdList.BINGODELAGUILD("exportar")
    f = ofi.ns.UI.exchange
    assert f.IsShown(f) and f.body.GetEditBox(f.body).GetText(f.body.GetEditBox(f.body)) == "BINGO1:\nUna"
    f.body.GetEditBox(f.body).SetText(f.body.GetEditBox(f.body), "BINGO1:\nOtra\nMás")
    f.importButton._scripts.OnClick(f.importButton)
    assert list(ofi.ns.Drafts().values()) == ["Otra", "Más"] and not f.IsShown(f)
    assert any("2 goals imported" in line for line in ofi.chat())
    me.lua.globals().SlashCmdList.BINGODELAGUILD("exportar")
    assert any("Only officers" in line for line in me.chat())


# the book (Pergamino) ----------------------------------------------------------------------------


def test_the_window_is_a_pergamino_book(me):
    me.run("ns.UI.Toggle()")
    f = me.ns.UI.frame
    assert me.run("return Pergamino.VERSION") == 7
    assert str(f.leather.texture).endswith("BingoDeLaGuild\\Libs\\Pergamino\\Media\\leather")
    assert f.pageL.texture.endswith("page") and f.pageR.texture.endswith("page") and f.spine.texture.endswith("spine")
    assert f.title.GetText(f.title) == "Guild Bingo"
    assert [k for k in f.tabOrder.values()] == ["carton", "liga", "oficiales", "errors"]
    assert me.run("return BingoDeLaGuildFrame.tabs.errors:IsShown()") is False  # hidden until there is an error
    assert f.selected == "carton" and f.pages.carton.right.IsShown(f.pages.carton.right)
    assert not f.pages.liga.right.IsShown(f.pages.liga.right)
    # the fonts are the library's own, read from this addon's copy
    font = me.run("return PergaminoBody")
    assert font.GetFont(font)[0].endswith("BingoDeLaGuild\\Libs\\Pergamino\\Fonts\\Alegreya-Regular.ttf")
    # no Blizzard frame template anywhere in the window
    assert f._template is None and f.close._template is None


def test_bookmarks_turn_the_page_and_have_tooltips(me):
    me.run("ns.UI.Toggle()")
    f = me.ns.UI.frame
    tab = f.tabs.liga
    tab._scripts.OnClick(tab)
    assert f.selected == "liga" and me.ns.UI.view == "league"
    assert f.pages.liga.right.IsShown(f.pages.liga.right) and not f.pages.carton.right.IsShown(f.pages.carton.right)
    assert f.tabs.liga.width == 164 and f.tabs.carton.width == 150  # the open bookmark sticks out more
    tab._scripts.OnEnter(tab)
    lines = me.run("return table.concat(GameTooltip.lines or {}, '\\n')")
    assert "one per square" in lines
    me.lua.globals().SlashCmdList.BINGODELAGUILD("liga")
    assert f.selected == "liga"


def border(cell):
    """The colour last given to a square's top edge (SetColorTexture r, g, b)."""
    calls = cell.edges[1]._calls
    last = calls[len(calls)]
    return (last[2], last[3], last[4])


def test_squares_are_stamped_todo_done_line_and_free(me):
    me.run("ns.UI.Toggle()")
    cells = me.ns.UI.cells
    free = cells[13]
    assert free.goalID == "free" and free.seal._shown and not free.wash._shown
    todo = next(c for c in cells.values() if c.goalID != "free")
    assert not todo.wash._shown and not todo.tick._shown and not todo.seal._shown
    me.ns.Toggle(todo.goalID)
    assert todo.wash._shown and todo.tick._shown
    assert border(todo) == pytest.approx((0.58, 0.44, 0.12))  # gold-deep border
    mark_row(me, 2)  # the free square's row: a line
    assert free.wash._shown and border(free) == pytest.approx((0.56, 0.16, 0.11))  # crimson


def test_officers_bookmark_only_for_officers():
    plain, ofi = Client().login(), officer()
    plain.run("ns.UI.Toggle()")
    assert not plain.ns.UI.frame.tabs.oficiales.IsShown(plain.ns.UI.frame.tabs.oficiales)
    ofi.run("ns.UI.Toggle()")
    f = ofi.ns.UI.frame
    assert f.tabs.oficiales.IsShown(f.tabs.oficiales)
    f.tabs.oficiales._scripts.OnClick(f.tabs.oficiales)
    assert f.selected == "oficiales" and f.publish.IsShown(f.publish)
    assert "No goals written" in f.draftsNote.GetText(f.draftsNote)
    ofi.lua.globals().SlashCmdList.BINGODELAGUILD("meta Bailar")
    rows = f.drafts.box.rows
    assert rows[1].name.GetText(rows[1].name) == "1. Bailar"
    # losing the rank sends you back to the card
    ofi.run("MOCK.officer = false")
    ofi.fire("GUILD_ROSTER_UPDATE")
    ofi.ns.UI.Refresh()
    assert f.selected == "carton" and not f.tabs.oficiales.IsShown(f.tabs.oficiales)


def test_empty_states_invite():
    alone = Client(guild=None).login()
    alone.run("ns.UI.Toggle()")
    note = alone.ns.UI.frame.note
    assert "not in a guild" in note.GetText(note) and "Join a guild" in note.GetText(note)
    me = Client().login()
    me.run("ns.UI.Toggle()")
    note = me.ns.UI.frame.note
    assert "Nobody else" in note.GetText(note) and "same card" in note.GetText(note)


def test_the_language_can_be_chosen_on_any_client(me):
    assert me.ns.GoalText(me.ns.GOAL["fall"]) == "Die from a fall" and me.ns.L.TITLE == "Guild Bingo"
    me.run("ns.UI.Toggle()")
    f = me.ns.UI.frame
    me.lua.globals().SlashCmdList.BINGODELAGUILD("idioma es")
    assert me.ns.db.settings.lang == "es" and me.ns.spanish
    assert me.ns.GoalText(me.ns.GOAL["fall"]) == "Morir de una caída"
    assert f.title.GetText(f.title) == "Bingo de la Guild" and f.tabs.liga.GetText(f.tabs.liga) == "Liga"
    assert any("Idioma: es" in line for line in me.chat())
    me.lua.globals().SlashCmdList.BINGODELAGUILD("idioma auto")
    assert not me.ns.spanish and f.title.GetText(f.title) == "Guild Bingo"
    me.lua.globals().SlashCmdList.BINGODELAGUILD("idioma klingon")
    assert any("/bingo idioma es | en | auto" in line for line in me.chat())
    # the setting survives a relog
    saved = Client(saved="BingoDeLaGuildDB = { settings = { lang = 'es' } }").login()
    assert saved.ns.spanish and saved.ns.L.TITLE == "Bingo de la Guild"
    # and an English choice on a Spanish client works the other way round
    es = Client(locale="esES").login()
    assert es.ns.spanish
    es.lua.globals().SlashCmdList.BINGODELAGUILD("idioma en")
    assert not es.ns.spanish and es.ns.L.TITLE == "Guild Bingo"


def test_the_exchange_is_a_parchment_card(me):
    ofi = officer()
    ofi.lua.globals().SlashCmdList.BINGODELAGUILD("exportar")
    f = ofi.ns.UI.exchange
    assert f._template is None and f.body._template == "ScrollingEditBoxTemplate"
    assert f.title.GetText(f.title) == "Export / import goals"
    f.close._scripts.OnClick(f.close)
    assert not f.IsShown(f)


# minimap button --------------------------------------------------------------------------------


def test_the_minimap_button_opens_the_card_and_remembers_where_it_was():
    me = Client().login()
    b = me.lua.globals().BingoDeLaGuildMinimapButton
    assert b is not None and b._shown is True
    assert b.icon.texture.endswith("BingoDeLaGuild\\Media\\icon")
    me.run("ns.MinimapButton():GetScript('OnClick')(ns.MinimapButton(), 'LeftButton')")
    assert me.run("return ns.UI.frame:IsShown()")
    me.run("ns.UI.Toggle(); ns.MinimapButton():GetScript('OnClick')(ns.MinimapButton(), 'RightButton')")
    assert me.run("return ns.UI.frame.selected") == "liga"
    me.run(
        "MOCK.cursorX, MOCK.cursorY = 1200, 500; local b = ns.MinimapButton();"
        " b:GetScript('OnDragStart')(b); b:GetScript('OnUpdate')(b); b:GetScript('OnDragStop')(b)"
    )
    assert me.run("return ns.db.settings.minimapAngle") == 0
    me.run("SlashCmdList.BINGODELAGUILD('minimapa off')")
    assert b._shown is False and me.run("return ns.db.settings.minimap") is False
    assert any("Minimap button off" in line for line in me.chat())
    # the next session keeps it hidden and in its place
    again = Client(saved=me.m.savedVariables("BingoDeLaGuildDB")).login()
    b2 = again.lua.globals().BingoDeLaGuildMinimapButton
    assert b2._shown is False and b2.angle == 0


def test_a_handler_error_is_kept_and_shown_not_thrown():
    me = Client()
    me.login()
    # a broken handler in the event frame: the guard keeps the error instead of a popup
    me.run("ns.Count = function() error('se rompio el conteo') end")
    me.fire("PLAYER_LEVEL_UP", 14)  # does not raise
    errs = me.run("return ns.db.errors")
    assert len(errs) == 1 and "se rompio el conteo" in errs[1].message and errs[1].label == "PLAYER_LEVEL_UP"
    assert sum(1 for line in me.m.chat.values() if "tuvo un error" in line or "had an error" in line) == 1
    # /bingo errores opens the book on the errors bookmark, now showing, with the text to copy
    me.lua.globals().SlashCmdList.BINGODELAGUILD("errores")
    f = me.run("return BingoDeLaGuildFrame")
    assert f.selected == "errors" and me.run("return BingoDeLaGuildFrame.tabs.errors:IsShown()") is True
    assert "se rompio el conteo" in me.run("return ns.UI.errors.area.box._text")
    me.run("ns.UI.errors.clear:GetScript('OnClick')()")
    assert me.run("return #ns.db.errors") == 0


def test_merging_the_minimap_buttons_hides_ours_and_the_hub_lists_it(me):
    b = me.lua.globals().BingoDeLaGuildMinimapButton
    entries = me.run("return Pergamino.MinimapHub.Entries()")
    assert [e.label for e in entries.values()] == ["Guild Bingo"]
    me.lua.globals().SlashCmdList.BINGODELAGUILD("minimapa juntar on")
    assert me.run("return ns.db.settings.minimapMerged") is True and me.run("return Pergamino.MinimapHub.IsMerged()") is True
    assert b._shown is False and me.lua.globals().PergaminoMinimapHub._shown is True
    again = Client(saved=me.save()).login()
    assert again.run("return Pergamino.MinimapHub.IsMerged()") is True
    again.lua.globals().SlashCmdList.BINGODELAGUILD("minimap merge off")
    assert again.lua.globals().BingoDeLaGuildMinimapButton._shown is True


def test_an_error_in_the_minimap_click_or_the_compartment_is_kept(me):
    me.run("ns.UI.Toggle = function() error('se rompio el carton') end")
    me.run("ns.MinimapButton():GetScript('OnClick')(ns.MinimapButton(), 'LeftButton')")
    me.run("BingoDeLaGuild_OnAddonCompartmentClick()")
    errs = me.run("return ns.guard.Errors()")
    assert sorted(e.label for e in errs.values()) == ["compartment", "minimap"]
