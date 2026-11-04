local _, ns = ...
local L = ns.L

-- Sharing cards with the guild through addon messages on the GUILD channel. Two messages, plain text:
--   C|<pool>|<week>|<25 marks>   my card ("1" = done)
--   Q|<pool>|<week>              "send me yours"
-- What arrives is only ever parsed with patterns and stored as text: nothing received is run.
-- Since every player of a guild draws the same card, only the marks travel.

ns.PREFIX = "BingoGuild1"

local MAX_LEN = 64 -- a card message is about 40 characters
local MAX_SENDERS = 1000 -- a guild holds at most 1000 members
local WINDOW, PER_WINDOW = 10, 5 -- at most 5 messages from one sender every 10 seconds

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

local retryPending = false
local function send(text)
	if not ns.CanSend() then
		return false
	end
	local function later()
		if not retryPending then
			retryPending = true
			C_Timer.After(15, function()
				retryPending = false
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

function ns.ShareNow()
	return send(table.concat({ "C", ns.POOL_VERSION, (ns.Week()), ns.Marks() }, "|"))
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

-- The cards of the guild for this week: sender -> { m = marks, t = time }.
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

local rate = {} -- sender -> { t = window start, n = messages in it }
local warnedVersion = {}
local lastReply, replyPending = 0, false

local function allowed(sender)
	local now = time()
	local r = rate[sender]
	if not r or now - r.t >= WINDOW then
		r = { t = now, n = 0 }
		rate[sender] = r
	end
	r.n = r.n + 1
	return r.n <= PER_WINDOW
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
	if sender == ns.Me() or not allowed(sender) then
		return
	end
	local kind, pool, week, marks = text:match("^([CQ])|(%d+)|(%d+)|?([01]*)$")
	if not kind then
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
		-- answer once, a little later, however many ask at the same time
		if not replyPending and time() - lastReply >= 20 then
			replyPending = true
			C_Timer.After(2 + math.random() * 6, function()
				replyPending = false
				lastReply = time()
				ns.ShareNow()
			end)
		end
		return
	end
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
	local hadLines = before and ns.Lines(before.m) or 0
	cards[sender] = { m = marks, t = time() }
	if ns.Lines(marks) > 0 and hadLines == 0 then
		ns.Print(L.SOMEONE_BINGO:format(sender))
	end
	ns.Fire("guild")
end
