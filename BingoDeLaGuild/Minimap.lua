local ADDON, ns = ...
local L = ns.L

-- The round button on the minimap's edge (Pergamino.MinimapButton): left click opens the card, right click the
-- league. Its angle lives in settings.minimapAngle; settings.minimap = false hides it (/bingo minimapa off). The
-- button is registered in the family's hub: with settings.minimapMerged the lib shows one button for every addon
-- that shares it (/bingo minimapa juntar on|off). Clicks go through the guard, so an error is kept, not thrown.

local button

function ns.MinimapButton()
	if button then
		return button
	end
	local s = ns.db.settings
	button = Pergamino.MinimapButton(ADDON .. "MinimapButton", {
		icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon",
		angle = s.minimapAngle,
		shown = s.minimap ~= false,
		onClick = function()
			ns.UI.Toggle()
		end,
		onRightClick = function()
			ns.UI.Toggle()
			if ns.UI.frame and ns.UI.frame:IsShown() then
				ns.UI.frame:SelectTab("liga")
			end
		end,
		onMove = function(angle)
			s.minimapAngle = angle
		end,
		tooltip = function(tip)
			tip:SetText(L.TITLE)
			tip:AddLine(L.MINIMAP_TIP, 1, 1, 1, true)
		end,
		guard = ns.guard,
		hub = { addon = L.TITLE, label = L.TITLE, order = 3 },
	})
	-- the family's choice (one button for all) lives in every addon's settings: the hub reads and keeps it
	Pergamino.MinimapHub.Bind(s)
	return button
end

-- /bingo minimapa juntar on|off: one button for the whole family (the lib keeps it for every addon)
function ns.SetMinimapMerged(merged)
	Pergamino.MinimapHub.Choose(merged) -- saved by the hub in every addon's settings
	ns.Print(merged and L.MINIMAP_MERGED_ON or L.MINIMAP_MERGED_OFF)
end

-- /bingo minimapa on|off
function ns.SetMinimapShown(shown)
	ns.db.settings.minimap = shown and true or false
	ns.MinimapButton():SetShown(shown)
	ns.Print(shown and L.MINIMAP_ON or L.MINIMAP_OFF)
end
