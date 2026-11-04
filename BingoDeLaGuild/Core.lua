local ADDON, ns = ...
local L = ns.L

-- Saved data (BingoDeLaGuildDB):
--   chars[Name-Realm].weeks[week] = { t = first seen, count = { die = 2 }, sets = { zone = { Elwynn = true } },
--                                     manual = { fall = true }, lines = n }
--   guilds[scope][week][sender] = { m = "0101…" (25 marks), t = when it arrived }

local listeners = {}
function ns.On(topic, fn)
	listeners[topic] = listeners[topic] or {}
	table.insert(listeners[topic], fn)
end
function ns.Fire(topic, ...)
	for _, fn in ipairs(listeners[topic] or {}) do
		fn(...)
	end
end

local KEEP_DAYS = 35 -- older weeks are dropped at login

function ns.InitDB()
	if type(BingoDeLaGuildDB) ~= "table" then
		BingoDeLaGuildDB = {}
	end
	local db = BingoDeLaGuildDB
	db.version = 1
	db.chars = type(db.chars) == "table" and db.chars or {}
	db.guilds = type(db.guilds) == "table" and db.guilds or {}
	ns.db = db
	local cutoff = time() - KEEP_DAYS * 86400
	for _, char in pairs(db.chars) do
		for week, w in pairs(char.weeks or {}) do
			if type(w) ~= "table" or (w.t or 0) < cutoff then
				char.weeks[week] = nil
			end
		end
	end
	for _, weeks in pairs(db.guilds) do
		for week, senders in pairs(weeks) do
			local newest = 0
			for _, s in pairs(senders) do
				newest = math.max(newest, s.t or 0)
			end
			if newest < cutoff then
				weeks[week] = nil
			end
		end
	end
end

function ns.Me()
	return UnitName("player")
end

function ns.CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName() or GetRealmName() or "?")
end

-- Whose card this is: the guild's (everyone in it draws the same one) or, outside a guild, just yours.
function ns.Scope()
	if IsInGuild() then
		local guild, _, _, realm = GetGuildInfo("player")
		if guild and not issecretvalue(guild) and guild ~= "" then
			return "g:" .. guild .. "-" .. (realm or GetNormalizedRealmName() or ""), true
		end
	end
	return "p:" .. ns.CharKey(), false
end

-- The week: identified by the weekly reset, so the whole realm changes card at the same moment.
-- Rounded to the hour so a few seconds of clock difference between players do not split the guild.
function ns.Week()
	local now = GetServerTime()
	local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
	if type(untilReset) == "number" and untilReset > 0 and not issecretvalue(untilReset) then
		local resetAt = math.floor((now + untilReset) / 3600 + 0.5) * 3600
		return tostring(resetAt), resetAt
	end
	-- no reset time: weeks from Monday 00:00 UTC (1970-01-05 was a Monday)
	local n = math.floor((now - 345600) / 604800) + 1
	return tostring(n), 345600 + n * 604800
end

-- A small random-number generator of our own (Park-Miller), so drawing a card never touches math.random,
-- which other addons share. Every product stays below 2^53, so Lua's doubles keep it exact.
local MOD = 2147483647
local function seedOf(s)
	local h = 7
	for i = 1, #s do
		h = (h * 31 + s:byte(i)) % MOD
	end
	return h == 0 and 1 or h
end

local cache = {}
-- The 25 squares: 24 goal ids drawn from the pool for this scope and week, and "free" in the middle (13).
function ns.Card(scope, week)
	scope, week = scope or ns.Scope(), week or ns.Week()
	local key = ns.POOL_VERSION .. "|" .. scope .. "|" .. week
	if cache[key] then
		return cache[key]
	end
	local seed = seedOf(key)
	local ids = {}
	for i, g in ipairs(ns.GOALS) do
		ids[i] = g.id
	end
	for i = #ids, 2, -1 do
		seed = (seed * 16807) % MOD
		local j = seed % i + 1
		ids[i], ids[j] = ids[j], ids[i]
	end
	local card = {}
	for i = 1, 24 do
		card[#card + 1] = ids[i]
		if #card == 12 then
			card[13] = "free"
		end
	end
	cache[key] = card
	return card
end

-- This character's record for the current week.
function ns.ThisWeek()
	local key = ns.CharKey()
	local char = ns.db.chars[key]
	if not char then
		char = { weeks = {} }
		ns.db.chars[key] = char
	end
	local week = ns.Week()
	local w = char.weeks[week]
	if not w then
		w = { t = time(), count = {}, sets = {}, manual = {}, lines = 0 }
		char.weeks[week] = w
	end
	return w
end

function ns.Progress(g)
	local w = ns.ThisWeek()
	return math.min(w.count[g.count] or 0, g.need)
end

function ns.Done(id)
	if id == "free" then
		return true
	end
	local g = ns.GOAL[id]
	if not g then
		return false
	end
	local w = ns.ThisWeek()
	return w.manual[id] == true or (g.count ~= nil and (w.count[g.count] or 0) >= g.need)
end

function ns.Marks(card)
	local out = {}
	for i, id in ipairs(card or ns.Card()) do
		out[i] = ns.Done(id) and "1" or "0"
	end
	return table.concat(out)
end

ns.LINES = {}
for r = 0, 4 do
	ns.LINES[#ns.LINES + 1] = { r * 5 + 1, r * 5 + 2, r * 5 + 3, r * 5 + 4, r * 5 + 5 }
	ns.LINES[#ns.LINES + 1] = { r + 1, r + 6, r + 11, r + 16, r + 21 }
end
ns.LINES[#ns.LINES + 1] = { 1, 7, 13, 19, 25 }
ns.LINES[#ns.LINES + 1] = { 5, 9, 13, 17, 21 }

-- How many full lines (rows, columns, diagonals) a 25-character marks string has, and which squares are in one.
function ns.Lines(marks)
	local n, inLine = 0, {}
	for _, line in ipairs(ns.LINES) do
		local full = true
		for _, i in ipairs(line) do
			if marks:sub(i, i) ~= "1" then
				full = false
				break
			end
		end
		if full then
			n = n + 1
			for _, i in ipairs(line) do
				inLine[i] = true
			end
		end
	end
	return n, inLine
end

function ns.CountMarks(marks)
	local _, n = marks:gsub("1", "")
	return n
end

local BINGO_COLOR = { r = 1, g = 0.82, b = 0 }

-- Something changed on this week's card: tell the window and the guild, and call bingo on a new line.
local function changed()
	local w = ns.ThisWeek()
	local lines = ns.Lines(ns.Marks())
	local card = ns.Scope()
	if w.linesCard ~= card then
		-- another card (you joined or left a guild): its lines are not new news
		w.linesCard, w.lines = card, lines
	elseif lines > (w.lines or 0) then
		RaidWarningUtil.AddMessage(L.YOU_BINGO, BINGO_COLOR)
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
	w.lines = lines
	ns.Fire("card")
	if ns.ShareSoon then
		ns.ShareSoon()
	end
end

-- A counter of the automatic goals went up. distinct: count each value once (zones, days).
function ns.Count(counter, distinct)
	if not ns.db then
		return
	end
	local w = ns.ThisWeek()
	local before = ns.Marks()
	if distinct ~= nil then
		if issecretvalue(distinct) or distinct == "" then
			return
		end
		w.sets[counter] = w.sets[counter] or {}
		if w.sets[counter][distinct] then
			return
		end
		w.sets[counter][distinct] = true
		local n = 0
		for _ in pairs(w.sets[counter]) do
			n = n + 1
		end
		w.count[counter] = n
	else
		w.count[counter] = (w.count[counter] or 0) + 1
	end
	if ns.Marks() ~= before then
		changed()
	else
		ns.Fire("card")
	end
end

-- Clicking a square. A goal that already counted itself done stays marked.
function ns.Toggle(id)
	local g = ns.GOAL[id]
	if not g then
		return false
	end
	local w = ns.ThisWeek()
	if w.manual[id] then
		w.manual[id] = nil
	elseif ns.Done(id) then
		return false
	else
		w.manual[id] = true
	end
	changed()
	return true
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.TITLE .. ":|r " .. msg)
end

ns.ADDON = ADDON
