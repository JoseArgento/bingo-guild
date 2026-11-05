local ADDON, ns = ...
local L = ns.L

-- What marks the automatic goals, plus login, the guild and the weekly reset.

local LOOT_PATTERNS
local function lootPatterns()
	if not LOOT_PATTERNS then
		LOOT_PATTERNS = {}
		for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE }) do
			if type(fmt) == "string" then
				local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
				p = p:gsub("%%%d+%%%$s", "(.+)"):gsub("%%%d+%%%$d", "%%d+"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
				LOOT_PATTERNS[#LOOT_PATTERNS + 1] = "^" .. p .. "$"
			end
		end
	end
	return LOOT_PATTERNS
end

local function groupHasGuildmate()
	local n = GetNumGroupMembers() or 0
	if n == 0 then
		return false
	end
	local raid = IsInRaid()
	for i = 1, raid and n or n - 1 do
		local unit = (raid and "raid" or "party") .. i
		local yes = UnitIsInMyGuild(unit)
		if yes and not issecretvalue(yes) and not UnitIsUnit(unit, "player") then
			return true
		end
	end
	return false
end

local currentWeek, currentScope
local lastDeath, zonePending

-- Inside one of Forever's new dungeons? GetInstanceInfo gives the localized name; the list is English (⏳ other
-- locales: those squares are clicked by hand).
local function newDungeonHere()
	local name, instanceType = GetInstanceInfo()
	if instanceType == "party" and type(name) == "string" and not issecretvalue(name) and ns.NEW_DUNGEONS[name] then
		return name
	end
end

local function isSkyborne()
	local race, raceFile = UnitRace("player")
	for _, v in ipairs({ raceFile, race }) do
		if type(v) == "string" and not issecretvalue(v) and v:lower():find("skyborne", 1, true) then
			return true
		end
	end
	return false
end

-- Legacy points come with achievements; Blizzard_LegacyAchievementOverrides.lua asks the same way, with
-- Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225 (LegacyConstantsDocumentation.lua, 1.60.1)
local LEGACY_CURRENCY = 4225
local function legacyPoints(achievementID)
	if type(achievementID) ~= "number" or issecretvalue(achievementID) then
		return 0
	end
	local f = C_Traits and C_Traits.GetTraitCurrencyForAchievement
	local amount = f and f(LEGACY_CURRENCY, achievementID)
	return (type(amount) == "number" and not issecretvalue(amount)) and amount or 0
end

local function checkCard()
	local week, scope = ns.Week(), ns.Scope()
	if week ~= currentWeek or scope ~= currentScope then
		local first = currentWeek == nil
		local previousWeek = currentWeek
		currentWeek, currentScope = week, scope
		if not first then
			if week ~= previousWeek then
				ns.Print(L.NEW_CARD)
			end
			ns.Fire("card")
		end
		if ns.CanSend() then
			ns.AskGuild()
			ns.ShareSoon()
		end
	end
end

local handlers = {
	PLAYER_DEAD = function()
		-- fires twice for one death in Forever (reported in the beta, 1.60.1)
		local now = GetTime()
		if lastDeath and now - lastDeath < 5 then
			return
		end
		lastDeath = now
		ns.Count("die")
	end,
	PLAYER_LEVEL_UP = function(level)
		ns.Count("level")
		if type(level) == "number" and level >= 10 and isSkyborne() then
			ns.Count("skyborne10", ns.CharKey()) -- ⏳ the race token of the Skyborne on a live client
		end
	end,
	ACHIEVEMENT_EARNED = function(achievementID)
		if legacyPoints(achievementID) > 0 then
			ns.Count("legacy")
		end
	end,
	PLAYER_ENTERING_WORLD = function()
		local name = newDungeonHere()
		if name then
			ns.Count("newdungeon", name)
		end
	end,
	ENCOUNTER_END = function(_, _, _, _, success)
		if success == 1 then
			ns.Count("boss")
		end
	end,
	QUEST_TURNED_IN = function()
		ns.Count("quest")
	end,
	SCREENSHOT_SUCCEEDED = function()
		if IsInGroup() then
			ns.Count("groupshot")
		end
	end,
	ZONE_CHANGED_NEW_AREA = function()
		-- right after a hearthstone, flight or portal the zone text can be the old one or empty: read it later
		if zonePending then
			return
		end
		zonePending = true
		C_Timer.After(2, function()
			zonePending = false
			ns.Count("zone", GetRealZoneText())
			local name = newDungeonHere()
			if name then
				ns.Count("newdungeon", name)
			end
		end)
	end,
	DUEL_FINISHED = function()
		ns.Count("duel")
	end,
	MAIL_SEND_SUCCESS = function()
		ns.Count("mail")
	end,
	AUCTION_HOUSE_SHOW = function()
		ns.Count("auction")
	end,
	PLAYER_CONTROL_LOST = function()
		-- a flight takes control away; check a moment later that it was the taxi
		C_Timer.After(1, function()
			if UnitOnTaxi("player") then
				ns.Count("taxi")
			end
		end)
	end,
	GROUP_ROSTER_UPDATE = function()
		if not ns.ThisWeek().count.guildgroup and groupHasGuildmate() then
			ns.Count("guildgroup")
		end
	end,
	PLAYER_TARGET_CHANGED = function()
		local c = UnitClassification("target")
		if c and not issecretvalue(c) and (c == "rare" or c == "rareelite") then
			ns.Count("rare")
		end
	end,
	CHAT_MSG_LOOT = function(text)
		if type(text) ~= "string" or issecretvalue(text) then
			return
		end
		for _, p in ipairs(lootPatterns()) do
			local link = text:match(p)
			if link then
				local quality = C_Item.GetItemQualityByID(link)
				if quality and not issecretvalue(quality) and quality >= 3 then
					ns.Count("blueloot")
				end
				return
			end
		end
	end,
	CHAT_MSG_ADDON = function(prefix, text, channel, sender)
		ns.OnAddonMessage(prefix, text, channel, sender)
	end,
	PLAYER_GUILD_UPDATE = checkCard,
	GUILD_ROSTER_UPDATE = checkCard,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			ns.InitDB()
			ns.SetLanguage(ns.db.settings.lang)
			frame:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
		for e in pairs(handlers) do
			frame:RegisterEvent(e)
		end
		ns.Count("day", date("%Y-%m-%d"))
		ns.Count("zone", GetRealZoneText())
		ns.MinimapButton()
		checkCard()
		-- the weekly reset can happen while you play
		C_Timer.NewTicker(60, function()
			ns.Count("day", date("%Y-%m-%d"))
			checkCard()
		end)
	elseif handlers[event] then
		handlers[event](...)
	end
end)

SLASH_BINGODELAGUILD1 = "/bingo"
SlashCmdList.BINGODELAGUILD = function(msg)
	local raw = strtrim(msg or "")
	msg = raw:lower()
	if msg == "sync" then
		if ns.CanSend() then
			ns.AskGuild()
			ns.ShareSoon()
			ns.Print(L.RESYNC)
		else
			local _, inGuild = ns.Scope()
			ns.Print(inGuild and L.TRIAL or L.NO_GUILD)
		end
	elseif msg == "liga" or msg == "league" then
		ns.UI.view = "league"
		ns.UI.Show()
	elseif msg:match("^meta ") then
		if ns.IAmOfficer() then
			ns.AddDraft(raw:sub(6)) -- as typed, not lowercased
			ns.Print(L.DRAFTS:format(#ns.Drafts(), table.concat(ns.Drafts(), " · ")))
		else
			ns.Print(L.NOT_OFFICER)
		end
	elseif msg:match("^sugerir ") or msg:match("^suggest ") then
		ns.UI.SendSuggestion(raw:sub(raw:find(" ") + 1))
	elseif msg == "sugerencias" or msg == "suggestions" then
		if ns.IAmOfficer() then
			local list = ns.Suggestions()
			ns.Print(L.SUGGESTIONS:format(#list))
			for _, s in ipairs(list) do
				ns.Print(s.by .. ": " .. s.text)
			end
			ns.UI.ReviewNext()
		else
			ns.Print(L.NOT_OFFICER)
		end
	elseif msg == "exportar" or msg == "export" then
		if ns.IAmOfficer() then
			ns.UI.ToggleExchange()
		else
			ns.Print(L.NOT_OFFICER)
		end
	elseif msg == "metas" then
		ns.Print(L.DRAFTS:format(#ns.Drafts(), table.concat(ns.Drafts(), " · ")))
	elseif msg == "borrar" then
		ns.ClearDrafts()
	elseif msg == "publicar" or msg == "publish" then
		if not ns.Publish() then
			ns.Print(ns.IAmOfficer() and L.DRAFTS:format(0, "") or L.NOT_OFFICER)
		end
	elseif msg:match("^idioma") or msg:match("^language") then
		local lang = msg:match("^%S+%s+(%S+)")
		if lang == "es" or lang == "en" or lang == "auto" then
			ns.db.settings.lang = lang
			ns.SetLanguage(lang)
			ns.Print(L.LANG_SET:format(lang))
		else
			ns.Print(L.LANG_HELP)
		end
	elseif msg:match("^minimapa") or msg:match("^minimap") then
		local on = msg:match("^%S+%s+(%S+)")
		if on == "on" or on == "off" then
			ns.SetMinimapShown(on == "on")
		else
			ns.SetMinimapShown(ns.db.settings.minimap == false)
		end
	elseif msg == "help" or msg == "ayuda" then
		ns.Print(L.HELP)
	else
		ns.UI.Toggle()
	end
end

function BingoDeLaGuild_OnAddonCompartmentClick()
	ns.UI.Toggle()
end
function BingoDeLaGuild_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(L.TITLE)
	GameTooltip:AddLine(L.COMPARTMENT, 1, 1, 1)
	GameTooltip:Show()
end
function BingoDeLaGuild_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-- Key binding (Bindings.xml) and its names in the key bindings panel.
_G["BingoDeLaGuild_Toggle"] = function()
	ns.UI.Toggle()
end
_G["BINDING_HEADER_BINGODELAGUILD"] = "Bingo de la Guild"
_G["BINDING_NAME_BINGODELAGUILD_TOGGLE"] = L.BINDING_TOGGLE
