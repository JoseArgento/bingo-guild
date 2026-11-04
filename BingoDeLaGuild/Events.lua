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

local function checkCard()
	local week, scope = ns.Week(), ns.Scope()
	if week ~= currentWeek or scope ~= currentScope then
		local first = currentWeek == nil
		currentWeek, currentScope = week, scope
		if not first then
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
	PLAYER_LEVEL_UP = function()
		ns.Count("level")
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
			frame:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
		for e in pairs(handlers) do
			frame:RegisterEvent(e)
		end
		ns.Count("day", date("%Y-%m-%d"))
		ns.Count("zone", GetRealZoneText())
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
	msg = strtrim((msg or ""):lower())
	if msg == "sync" then
		if ns.CanSend() then
			ns.AskGuild()
			ns.ShareSoon()
			ns.Print(L.RESYNC)
		else
			local _, inGuild = ns.Scope()
			ns.Print(inGuild and L.TRIAL or L.NO_GUILD)
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
