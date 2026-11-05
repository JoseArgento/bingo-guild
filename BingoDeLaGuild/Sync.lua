local _, ns = ...
local L = ns.L

-- Sharing cards with the guild through addon messages on the GUILD channel. Plain text, "|" between fields:
--   C|<pool>|<week>|<card>|<25 marks>   my marks ("1" = done) on the card named <card> (ns.CardKey)
--   Q|<pool>|<week>                     "send me yours"
--   K|<pool>|<week>|<ver>|<count>       an officer's card for the week: how many goals it has...
--   G|<pool>|<week>|<ver>|<i>|<text>    ...and each of them
--   S|<pool>|<week>|<text>              "I suggest this goal" (anyone; only officers keep them)
-- What arrives is only ever parsed with patterns and stored as text: nothing received is run. Marks are only
-- compared between players with the same card. An officer's card is only taken from someone whose guild rank
-- is the leader's or the one under it (settings.officerRank), checked in the guild roster.

ns.PREFIX = "BingoGuild1"

local MAX_LEN = 120 -- a goal message is the longest: 50 bytes of text plus the fields
local MAX_SENDERS = 1000 -- a guild holds at most 1000 members
local BUCKETS = {
	normal = { window = 10, per = 5 }, -- at most 5 card or question messages from one sender every 10 seconds
	officer = { window = 60, per = 40 }, -- an officer's card is up to 25 messages
}

local SUCCESS = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
local RETRY = {}
if Enum.SendAddonMessageResult then
	for _, k in ipairs({ "AddonMessageThrottle", "ChannelThrottle", "AddOnMessageLockdown", "GeneralError" }) do
		if Enum.SendAddonMessageResult[k] then
			RETRY[Enum.SendAddonMessageResult[k]] = true
		end
	end
end

function ns.IsTrial()
	return (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) or false
end

function ns.CanSend()
	local _, inGuild = ns.Scope()
	return inGuild and not ns.IsTrial()
end

local retryPending = {}
local function send(text)
	if not ns.CanSend() then
		return false
	end
	local function later()
		if not retryPending[text] then
			retryPending[text] = true
			C_Timer.After(15, function()
				retryPending[text] = nil
				send(text)
			end)
		end
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		later()
		return false
	end
	local result = C_ChatInfo.SendAddonMessage(ns.PREFIX, text, "GUILD")
	if result ~= nil and result ~= SUCCESS then
		if RETRY[result] then
			later()
		end
		return false
	end
	return true
end

-- Several messages one after the other, a little apart, so the game does not throttle them.
local function sendSpaced(messages)
	for i, text in ipairs(messages) do
		C_Timer.After(0.4 * (i - 1), function()
			send(text)
		end)
	end
end

function ns.ShareNow()
	local card = ns.Card()
	return send(table.concat({ "C", ns.POOL_VERSION, (ns.Week()), ns.CardKey(card), ns.Marks(card) }, "|"))
end

local sharePending = false
function ns.ShareSoon()
	if sharePending or not ns.CanSend() then
		return
	end
	sharePending = true
	C_Timer.After(3, function()
		sharePending = false
		ns.ShareNow()
	end)
end

function ns.AskGuild()
	return send(table.concat({ "Q", ns.POOL_VERSION, (ns.Week()) }, "|"))
end

-- Officers ----------------------------------------------------------------------------------------

function ns.IAmOfficer()
	local _, inGuild = ns.Scope()
	return inGuild and C_GuildInfo.IsGuildOfficer() == true
end

-- Is this guildmate allowed to publish a card? Looked up in the roster: rank 0 is the leader.
function ns.IsOfficer(sender)
	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local name, _, rankIndex = GetGuildRosterInfo(i)
		if name and not issecretvalue(name) and Ambiguate(name, "none") == sender then
			return type(rankIndex) == "number" and rankIndex <= (ns.db.settings.officerRank or 1)
		end
	end
	C_GuildInfo.GuildRoster() -- not loaded yet: ask for it, the next card will find them
	return false
end

function ns.Drafts()
	local scope = ns.Scope()
	ns.db.drafts[scope] = ns.db.drafts[scope] or {}
	return ns.db.drafts[scope]
end

function ns.AddDraft(text)
	text = ns.CleanGoal(text)
	local drafts = ns.Drafts()
	if not text or #drafts >= 24 then
		return false
	end
	drafts[#drafts + 1] = text
	ns.Fire("card")
	return true
end

function ns.ClearDrafts()
	wipe(ns.Drafts())
	ns.Fire("card")
end

-- The goal list as text, to keep or to pass to another officer: a header line and one goal per line.
ns.EXPORT_HEADER = "BINGO1:"

function ns.ExportGoals()
	local drafts = ns.Drafts()
	if #drafts == 0 then
		return nil
	end
	return ns.EXPORT_HEADER .. "\n" .. table.concat(drafts, "\n")
end

-- Pasted text back into the drafts (replacing them). Each line is cleaned like a received goal; at most 24.
-- Returns how many came in, or nil when the text is not an export.
function ns.ImportGoals(text)
	if type(text) ~= "string" then
		return nil
	end
	local first, rest = text:match("^%s*(BINGO1:)[ \t]*\r?\n?(.*)$")
	if first ~= ns.EXPORT_HEADER then
		return nil
	end
	local goals = {}
	for line in (rest .. "\n"):gmatch("([^\n]*)\n") do
		local goal = ns.CleanGoal(line)
		if goal then
			goals[#goals + 1] = goal
			if #goals == 24 then
				break
			end
		end
	end
	local drafts = ns.Drafts()
	wipe(drafts)
	for i, goal in ipairs(goals) do
		drafts[i] = goal
	end
	ns.Fire("card")
	return #goals
end

-- Suggestions: anyone in the guild may propose a goal; officers see them and add or drop them.
local MAX_SUGGESTIONS = 50

function ns.Suggest(text)
	text = ns.CleanGoal(text)
	if not text then
		return false
	end
	return send(table.concat({ "S", ns.POOL_VERSION, (ns.Week()), text }, "|"))
end

function ns.Suggestions()
	local scope = ns.Scope()
	ns.db.suggest[scope] = ns.db.suggest[scope] or {}
	return ns.db.suggest[scope]
end

local function onSuggestion(sender, text)
	if not ns.IAmOfficer() then
		return
	end
	text = ns.CleanGoal(text)
	if not text then
		return
	end
	local list = ns.Suggestions()
	for _, s in ipairs(list) do
		if s.by == sender and s.text == text then
			return
		end
	end
	if #list >= MAX_SUGGESTIONS then
		return
	end
	list[#list + 1] = { by = sender, text = text, t = time() }
	ns.Fire("suggest")
end

-- Take suggestion i: onto the drafts (accept) or just away (drop). Returns the suggestion.
function ns.TakeSuggestion(i, accept)
	local list = ns.Suggestions()
	local s = table.remove(list, i)
	if s and accept then
		ns.AddDraft(s.text)
	end
	ns.Fire("suggest")
	return s
end

local function cardMessages(card)
	local week = ns.Week()
	local out = { table.concat({ "K", ns.POOL_VERSION, week, card.ver, #card.goals }, "|") }
	for i, text in ipairs(card.goals) do
		out[#out + 1] = table.concat({ "G", ns.POOL_VERSION, week, card.ver, i, text }, "|")
	end
	return out
end

local function storeOfficerCard(scope, week, card)
	ns.db.officer[scope] = ns.db.officer[scope] or {}
	ns.db.officer[scope][week] = card
end

-- Publish this week's card from the drafts. Only for officers; everyone's card changes to it.
function ns.Publish()
	if not ns.IAmOfficer() then
		return false
	end
	local drafts = ns.Drafts()
	if #drafts == 0 then
		return false
	end
	local goals = {}
	for i, text in ipairs(drafts) do
		goals[i] = text
	end
	local scope, week = ns.Scope(), ns.Week()
	local card = { by = ns.Me(), ver = time(), goals = goals, t = time() }
	storeOfficerCard(scope, week, card)
	sendSpaced(cardMessages(card))
	ns.Fire("card")
	ns.ShareSoon()
	return true
end

-- Receiving ---------------------------------------------------------------------------------------

-- The cards of the guild for this week: sender -> { m = marks, k = card key, t = time }.
function ns.GuildCards()
	local scope, inGuild = ns.Scope()
	if not inGuild then
		return {}
	end
	local week = ns.Week()
	local weeks = ns.db.guilds[scope]
	if not weeks then
		weeks = {}
		ns.db.guilds[scope] = weeks
	end
	weeks[week] = weeks[week] or {}
	return weeks[week]
end

-- Only the guildmates who play the same card as you.
function ns.SameCard()
	local key = ns.CardKey()
	local out = {}
	for sender, c in pairs(ns.GuildCards()) do
		if c.k == key then
			out[sender] = c
		end
	end
	return out
end

local rate = {} -- bucket .. sender -> { t = window start, n = messages in it }
local warnedVersion = {}
local lastReply, replyPending = 0, false
local lastCardReply = 0
local pending = {} -- sender -> { week, ver, count, goals = {} } an officer's card arriving

local function allowed(sender, bucket)
	local b = BUCKETS[bucket]
	local now = time()
	local key = bucket .. sender
	local r = rate[key]
	if not r or now - r.t >= b.window then
		r = { t = now, n = 0 }
		rate[key] = r
	end
	r.n = r.n + 1
	return r.n <= b.per
end

local function onMarks(sender, cardKey, marks)
	if #marks ~= 25 or marks:sub(13, 13) ~= "1" then
		return
	end
	local cards = ns.GuildCards()
	local before = cards[sender]
	if not before then
		local n = 0
		for _ in pairs(cards) do
			n = n + 1
		end
		if n >= MAX_SENDERS then
			return
		end
	end
	local same = cardKey == ns.CardKey()
	local hadLines = (before and before.k == cardKey) and ns.Lines(before.m) or 0
	cards[sender] = { m = marks, k = cardKey, t = time() }
	if same and ns.Lines(marks) > 0 and hadLines == 0 then
		ns.Print(L.SOMEONE_BINGO:format(sender))
	end
	ns.Fire("guild")
end

local function onOfficerPart(sender, kind, week, ver, a, b)
	if not ns.IsOfficer(sender) then
		return
	end
	ver = tonumber(ver)
	local current = ns.OfficerCard()
	if current and current.ver >= ver then
		return -- already have this one or a newer one
	end
	local p = pending[sender]
	if not p or p.ver ~= ver then
		p = { week = week, ver = ver, goals = {} }
		pending[sender] = p
	end
	if kind == "K" then
		local count = tonumber(a)
		if not count or count < 1 or count > 24 then
			pending[sender] = nil
			return
		end
		p.count = count
	else
		local i = tonumber(a)
		local text = ns.CleanGoal(b)
		if not i or i < 1 or i > 24 or not text then
			return
		end
		p.goals[i] = text
	end
	if p.count then
		for i = 1, p.count do
			if not p.goals[i] then
				return
			end
		end
		local goals = {}
		for i = 1, p.count do
			goals[i] = p.goals[i]
		end
		pending[sender] = nil
		storeOfficerCard(ns.Scope(), week, { by = sender, ver = ver, goals = goals, t = time() })
		ns.Print(L.OFFICER_CARD:format(sender))
		ns.Fire("card")
		ns.ShareSoon()
	end
end

function ns.OnAddonMessage(prefix, text, channel, sender)
	if prefix ~= ns.PREFIX or channel ~= "GUILD" then
		return
	end
	if issecretvalue(text) or issecretvalue(sender) or type(text) ~= "string" or type(sender) ~= "string" then
		return
	end
	if #text > MAX_LEN or #sender > 64 then
		return
	end
	sender = Ambiguate(sender, "none")
	if sender == ns.Me() then
		return
	end
	local kind, pool, week, rest = text:match("^([CQKGS])|(%d+)|(%d+)|?(.*)$")
	if not kind or not allowed(sender, (kind == "K" or kind == "G") and "officer" or "normal") then
		return
	end
	if tonumber(pool) ~= ns.POOL_VERSION then
		if not warnedVersion[sender] then
			warnedVersion[sender] = true
			ns.Print(L.OTHER_VERSION:format(sender))
		end
		return
	end
	if week ~= ns.Week() then
		return -- an old or a future card: not this week's
	end
	if kind == "Q" then
		if rest ~= "" then
			return
		end
		-- answer once, a little later, however many ask at the same time
		if not replyPending and time() - lastReply >= 20 then
			replyPending = true
			C_Timer.After(2 + math.random() * 6, function()
				replyPending = false
				lastReply = time()
				ns.ShareNow()
			end)
		end
		-- the officer who published this week's card sends it again for whoever just arrived
		local mine = ns.OfficerCard()
		if mine and mine.by == ns.Me() and time() - lastCardReply >= 60 then
			lastCardReply = time()
			C_Timer.After(1, function()
				sendSpaced(cardMessages(mine))
			end)
		end
	elseif kind == "C" then
		local cardKey, marks = rest:match("^(%x%x%x%x%x%x)|([01]+)$")
		if cardKey then
			onMarks(sender, cardKey, marks)
		end
	elseif kind == "K" then
		local ver, count = rest:match("^(%d+)|(%d+)$")
		if ver then
			onOfficerPart(sender, "K", week, ver, count)
		end
	elseif kind == "G" then
		local ver, i, goal = rest:match("^(%d+)|(%d+)|(.+)$")
		if ver then
			onOfficerPart(sender, "G", week, ver, i, goal)
		end
	elseif kind == "S" then
		if rest ~= "" then
			onSuggestion(sender, rest)
		end
	end
end
