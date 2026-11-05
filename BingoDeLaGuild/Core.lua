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
	db.officer = type(db.officer) == "table" and db.officer or {} -- [scope][week] = { by, ver, goals }
	db.drafts = type(db.drafts) == "table" and db.drafts or {} -- [scope] = { "goal", ... } an officer is writing
	db.suggest = type(db.suggest) == "table" and db.suggest or {} -- [scope] = { { by, text, t }, ... } for officers
	db.settings = type(db.settings) == "table" and db.settings or {}
	db.settings.officerRank = db.settings.officerRank or 1 -- cards are accepted from the leader (0) and rank 1
	ns.db = db
	local cutoff = time() - KEEP_DAYS * 86400
	for _, char in pairs(db.chars) do
		for week, w in pairs(char.weeks or {}) do
			if type(w) ~= "table" or (w.t or 0) < cutoff then
				char.weeks[week] = nil
			end
		end
	end
	for _, weeks in pairs(db.officer) do
		for week, card in pairs(weeks) do
			if type(card) ~= "table" or (card.t or 0) < cutoff then
				weeks[week] = nil
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

function ns.Hash(s)
	return seedOf(s)
end

-- The card an officer published for this guild and week, if any: { by, ver, goals = { "text", ... } }.
function ns.OfficerCard(scope, week)
	scope, week = scope or ns.Scope(), week or ns.Week()
	local byScope = ns.db and ns.db.officer and ns.db.officer[scope]
	return byScope and byScope[week]
end

local cache = {}
-- The 25 squares, with "free" in the middle (13). Without an officer's card: 24 goals drawn from the list
-- for this scope and week, so everyone in the guild draws the same. With one: the officer's goals plus goals
-- from the list up to 24, in an order drawn the same way for everyone.
function ns.Card(scope, week)
	scope, week = scope or ns.Scope(), week or ns.Week()
	local officer = ns.OfficerCard(scope, week)
	local key = ns.POOL_VERSION .. "|" .. scope .. "|" .. week .. "|" .. (officer and officer.ver or "")
	if cache[key] then
		return cache[key]
	end
	local seed = seedOf(key)
	local function shuffle(ids)
		for i = #ids, 2, -1 do
			seed = (seed * 16807) % MOD
			local j = seed % i + 1
			ids[i], ids[j] = ids[j], ids[i]
		end
		return ids
	end
	local ids = {}
	for i, g in ipairs(ns.GOALS) do
		ids[i] = g.id
	end
	shuffle(ids)
	local chosen = {}
	if officer then
		for i = 1, math.min(#officer.goals, 24) do
			chosen[#chosen + 1] = "c" .. i
		end
	end
	for _, id in ipairs(ids) do
		if #chosen >= 24 then
			break
		end
		chosen[#chosen + 1] = id
	end
	if officer then
		shuffle(chosen)
	end
	local card = {}
	for i = 1, 24 do
		card[#card + 1] = chosen[i]
		if #card == 12 then
			card[13] = "free"
		end
	end
	cache[key] = card
	return card
end

-- A short name for a card, so marks are only compared between players who have the same one.
function ns.CardKey(card)
	return string.format("%06x", ns.Hash(table.concat(card or ns.Card(), ",")) % 16777216)
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
	local g = ns.Goal(id)
	if not g then
		return false
	end
	local w = ns.ThisWeek()
	if w.manual[id] == true then
		return true
	end
	if g.set then
		return (w.sets[g.set] and w.sets[g.set][g.key]) == true
	end
	return g.count ~= nil and (w.count[g.count] or 0) >= g.need
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
	w.marks = ns.Marks() -- kept for the league table
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
	local g = ns.Goal(id)
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

-- Points of a card for the league: one per square and 5 more per full line.
function ns.Points(marks)
	return ns.CountMarks(marks) + 5 * ns.Lines(marks)
end

-- The league: everyone's points added up over the weeks kept (about the last five).
-- { { name, points, weeks, bingos } }, best first. Yours come from your own record of each week.
function ns.League()
	local scope, inGuild = ns.Scope()
	local totals = {}
	local function add(name, marks)
		local t = totals[name] or { name = name, points = 0, weeks = 0, bingos = 0 }
		t.points = t.points + ns.Points(marks)
		t.weeks = t.weeks + 1
		if ns.Lines(marks) > 0 then
			t.bingos = t.bingos + 1
		end
		totals[name] = t
	end
	if inGuild then
		for _, senders in pairs(ns.db.guilds[scope] or {}) do
			for sender, c in pairs(senders) do
				if type(c) == "table" and type(c.m) == "string" and #c.m == 25 then
					add(sender, c.m)
				end
			end
		end
	end
	local char = ns.db.chars[ns.CharKey()]
	for _, w in pairs(char and char.weeks or {}) do
		if type(w.marks) == "string" and #w.marks == 25 then
			add(ns.Me(), w.marks)
		end
	end
	local out = {}
	for _, t in pairs(totals) do
		out[#out + 1] = t
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.name < b.name
	end)
	return out
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.TITLE .. ":|r " .. msg)
end

ns.ADDON = ADDON
