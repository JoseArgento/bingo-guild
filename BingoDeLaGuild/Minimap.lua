local ADDON, ns = ...
local L = ns.L

-- The round button on the minimap's edge (Pergamino.MinimapButton): left click opens the card, right click the
-- league. Its angle lives in settings.minimapAngle; settings.minimap = false hides it (/bingo minimapa off).

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
		onClick = function(which)
			if which == "RightButton" then
				ns.UI.Toggle()
				if ns.UI.frame and ns.UI.frame:IsShown() then
					ns.UI.frame:SelectTab("liga")
				end
			else
				ns.UI.Toggle()
			end
		end,
		onMove = function(angle)
			s.minimapAngle = angle
		end,
		tooltip = function(tip)
			tip:SetText(L.TITLE)
			tip:AddLine(L.MINIMAP_TIP, 1, 1, 1, true)
		end,
	})
	return button
end

-- /bingo minimapa on|off
function ns.SetMinimapShown(shown)
	ns.db.settings.minimap = shown and true or false
	ns.MinimapButton():SetShown(shown)
	ns.Print(shown and L.MINIMAP_ON or L.MINIMAP_OFF)
end
