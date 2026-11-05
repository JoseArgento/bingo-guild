local ADDON, ns = ...
local L = ns.L

-- The card window: 5x5 squares on the left, the guild's cards on the right. Built the first time it opens.

local CELL_W, CELL_H, GAP = 92, 66, 4
local GRID_W = CELL_W * 5 + GAP * 4
local SIDE_W = 140
local LIST_ROWS = 12

local COLORS = {
	todo = { 0.08, 0.08, 0.1, 0.85 },
	done = { 0.16, 0.42, 0.18, 0.9 },
	line = { 0.62, 0.45, 0.08, 0.95 },
	free = { 0.35, 0.28, 0.12, 0.9 },
}

local UI = {}
ns.UI = UI
UI.view = "week" -- or "league"

StaticPopupDialogs.BINGODELAGUILD_GOAL = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 50,
	OnShow = function(dialog)
		dialog:GetEditBox():SetText("")
		dialog:GetEditBox():SetFocus()
	end,
	OnAccept = function(dialog)
		ns.AddDraft(dialog:GetEditBox():GetText())
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		ns.AddDraft(editBox:GetText())
		dialog:Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

-- anyone proposes a goal for the officers
StaticPopupDialogs.BINGODELAGUILD_SUGGEST = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 50,
	OnShow = function(dialog)
		dialog:GetEditBox():SetText("")
		dialog:GetEditBox():SetFocus()
	end,
	OnAccept = function(dialog)
		ns.UI.SendSuggestion(dialog:GetEditBox():GetText())
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		ns.UI.SendSuggestion(editBox:GetText())
		dialog:Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

-- an officer goes through the suggestions one by one: add it, drop it, or later
StaticPopupDialogs.BINGODELAGUILD_REVIEW = {
	text = "%s",
	button1 = ADD,
	button2 = DELETE,
	button3 = CANCEL,
	OnAccept = function()
		ns.TakeSuggestion(1, true)
		ns.UI.ReviewNext()
	end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then
			ns.TakeSuggestion(1, false)
			ns.UI.ReviewNext()
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function UI.SendSuggestion(text)
	if ns.Suggest(text) then
		ns.Print(L.SUGGESTED)
	else
		local _, inGuild = ns.Scope()
		ns.Print(not inGuild and L.NO_GUILD or ns.IsTrial() and L.TRIAL or L.CANT_SEND)
	end
end

function UI.ReviewNext()
	local s = ns.Suggestions()[1]
	if s then
		StaticPopup_Show("BINGODELAGUILD_REVIEW", L.REVIEW:format(s.by, s.text))
	end
end

local function names(list, max)
	if #list <= max then
		return table.concat(list, ", ")
	end
	local shown = {}
	for i = 1, max do
		shown[i] = list[i]
	end
	return table.concat(shown, ", ") .. " +" .. (#list - max)
end

local function cellTooltip(cell)
	local id = cell.goalID
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if id == "free" then
		GameTooltip:SetText(L.FREE)
		GameTooltip:Show()
		return
	end
	local g = ns.Goal(id)
	GameTooltip:SetText(ns.GoalText(g), 1, 1, 1, 1, true)
	if g.custom then
		local card = ns.OfficerCard()
		GameTooltip:AddLine(L.CARD_BY:format(card and card.by or "?"), 0.7, 0.7, 0.7)
	end
	if g.count or g.set then
		GameTooltip:AddLine(ns.Done(id) and L.AUTO or L.AUTO_TOO, 0.7, 0.7, 0.7, true)
		if g.count and g.need > 1 then
			GameTooltip:AddLine(L.PROGRESS:format(ns.Progress(g), g.need), 1, 0.82, 0)
		end
	else
		GameTooltip:AddLine(L.MANUAL, 0.7, 0.7, 0.7, true)
	end
	local have = {}
	for sender, c in pairs(ns.SameCard()) do
		if c.m:sub(cell.index, cell.index) == "1" then
			have[#have + 1] = sender
		end
	end
	if #have > 0 then
		table.sort(have)
		GameTooltip:AddLine(L.HAVE_IT:format(names(have, 8)), 0.5, 0.9, 0.5, true)
	end
	GameTooltip:Show()
end

local function build()
	local FRAME = ADDON .. "Frame"
	local f = CreateFrame("Frame", FRAME, UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(14 + GRID_W + 12 + SIDE_W + 12, 440)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	f.TitleText:SetText(L.TITLE)
	tinsert(UISpecialFrames, FRAME)
	UI.frame = f

	f.week = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.week:SetPoint("TOPLEFT", 16, -34)
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.status:SetPoint("TOPLEFT", 16 + GRID_W - 200, -34)
	f.status:SetWidth(200)
	f.status:SetJustifyH("RIGHT")

	local grid = CreateFrame("Frame", nil, f)
	grid:SetPoint("TOPLEFT", 14, -58)
	grid:SetSize(GRID_W, CELL_H * 5 + GAP * 4)
	UI.cells = {}
	for i = 1, 25 do
		local cell = CreateFrame("Button", nil, grid)
		cell:SetSize(CELL_W, CELL_H)
		local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
		cell:SetPoint("TOPLEFT", col * (CELL_W + GAP), -row * (CELL_H + GAP))
		cell.index = i
		cell.bg = cell:CreateTexture(nil, "BACKGROUND")
		cell.bg:SetAllPoints()
		local hl = cell:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell.text:SetPoint("TOPLEFT", 4, -4)
		cell.text:SetPoint("BOTTOMRIGHT", -4, 14)
		cell.text:SetJustifyH("CENTER")
		cell.text:SetJustifyV("MIDDLE")
		cell.text:SetWordWrap(true)
		cell.progress = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		cell.progress:SetPoint("BOTTOM", 0, 3)
		cell:SetScript("OnClick", function(self)
			if self.goalID ~= "free" and ns.Toggle(self.goalID) then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			end
		end)
		cell:SetScript("OnEnter", cellTooltip)
		cell:SetScript("OnLeave", GameTooltip_Hide)
		UI.cells[i] = cell
	end

	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", grid, "TOPRIGHT", 12, 0)
	side:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	f.side = side
	local head = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT")
	head:SetText(L.GUILD)
	f.head = head
	UI.rows = {}
	for i = 1, LIST_ROWS do
		local row = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row:SetPoint("TOPLEFT", 0, -6 - i * 16)
		row:SetWidth(SIDE_W)
		row:SetJustifyH("LEFT")
		UI.rows[i] = row
	end
	f.note = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.note:SetPoint("TOPLEFT", 0, -16 - (LIST_ROWS + 1) * 16)
	f.note:SetWidth(SIDE_W)
	f.note:SetJustifyH("LEFT")
	f.note:SetWordWrap(true)

	f.league = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.league:SetSize(SIDE_W, 22)
	f.league:SetPoint("BOTTOM", 0, 28)
	f.league:SetScript("OnClick", function()
		UI.view = UI.view == "league" and "week" or "league"
		UI.Refresh()
	end)

	-- officers write this week's goals and publish them
	f.addGoal = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.addGoal:SetSize(SIDE_W, 22)
	f.addGoal:SetPoint("BOTTOM", f.league, "TOP", 0, 56)
	f.addGoal:SetText(L.ADD_GOAL)
	f.addGoal:SetScript("OnClick", function()
		StaticPopup_Show("BINGODELAGUILD_GOAL", L.GOAL_PROMPT)
	end)
	f.publish = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.publish:SetSize(SIDE_W, 22)
	f.publish:SetPoint("TOP", f.addGoal, "BOTTOM", 0, -4)
	f.publish:SetScript("OnClick", function()
		ns.Publish()
	end)
	f.review = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.review:SetSize(SIDE_W, 22)
	f.review:SetPoint("BOTTOM", f.addGoal, "TOP", 0, 4)
	f.review:SetScript("OnClick", UI.ReviewNext)
	f.exchange = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.exchange:SetSize(SIDE_W, 22)
	f.exchange:SetPoint("BOTTOM", f.review, "TOP", 0, 4)
	f.exchange:SetText(L.EXCHANGE)
	f.exchange:SetScript("OnClick", function()
		UI.ToggleExchange()
	end)
	-- anyone in the guild proposes a goal to the officers
	f.suggest = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.suggest:SetSize(SIDE_W, 22)
	f.suggest:SetPoint("BOTTOM", f.league, "TOP", 0, 4)
	f.suggest:SetText(L.SUGGEST)
	f.suggest:SetScript("OnClick", function()
		StaticPopup_Show("BINGODELAGUILD_SUGGEST", L.SUGGEST_PROMPT)
	end)

	f.announce = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
	f.announce:SetSize(SIDE_W, 24)
	f.announce:SetPoint("BOTTOM")
	f.announce:SetText(L.ANNOUNCE)
	f.announce:SetScript("OnClick", function()
		-- only ever from this click: the addon never writes in chat by itself
		C_ChatInfo.SendChatMessage(L.ANNOUNCE_TEXT:format(ns.CountMarks(ns.Marks())), "GUILD")
		f.announce:Disable()
	end)

	f:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		UI.Refresh()
	end)
	f:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
	end)
	return f
end

local function paint(tex, c)
	tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

function UI.Refresh()
	local f = UI.frame
	if not f or not f:IsShown() then
		return
	end
	local _, resetAt = ns.Week()
	local officer = ns.OfficerCard()
	f.week:SetText(L.WEEK_UNTIL:format(date("%d/%m %H:%M", resetAt)) .. (officer and ("  ·  " .. L.CARD_BY:format(officer.by)) or ""))
	local card = ns.Card()
	local marks = ns.Marks(card)
	local lines, inLine = ns.Lines(marks)
	local count = ns.CountMarks(marks)
	if lines > 1 then
		f.status:SetText(L.BINGO_LINES:format(lines))
	elseif lines == 1 then
		f.status:SetText(L.BINGO)
	else
		f.status:SetText(L.MARKED:format(count))
	end
	for i, cell in ipairs(UI.cells) do
		local id = card[i]
		cell.goalID = id
		local done = marks:sub(i, i) == "1"
		if id == "free" then
			cell.text:SetText(L.FREE)
			cell.progress:SetText("")
			paint(cell.bg, inLine[i] and COLORS.line or COLORS.free)
		else
			local g = ns.Goal(id)
			cell.text:SetText(ns.GoalText(g))
			if g.count and g.need > 1 and not done then
				cell.progress:SetText(ns.Progress(g) .. "/" .. g.need)
			else
				cell.progress:SetText("")
			end
			paint(cell.bg, inLine[i] and COLORS.line or done and COLORS.done or COLORS.todo)
		end
	end

	-- the guild: this week's cards (same card as yours), or the league of the last weeks
	local list = {}
	if UI.view == "league" then
		f.head:SetText(L.LEAGUE_HEAD)
		for _, e in ipairs(ns.League()) do
			list[#list + 1] = { name = e.name, text = e.name .. "  " .. L.POINTS:format(e.points) }
		end
	else
		f.head:SetText(L.GUILD)
		for sender, c in pairs(ns.SameCard()) do
			list[#list + 1] = { name = sender, lines = ns.Lines(c.m), marks = ns.CountMarks(c.m) }
		end
		table.sort(list, function(a, b)
			if a.lines ~= b.lines then
				return a.lines > b.lines
			end
			if a.marks ~= b.marks then
				return a.marks > b.marks
			end
			return a.name < b.name
		end)
		for _, e in ipairs(list) do
			e.text = e.name .. "  " .. e.marks .. (e.lines > 0 and ("  |cffffd100" .. L.BINGO .. "|r") or "")
		end
	end
	for i, row in ipairs(UI.rows) do
		row:SetText(list[i] and list[i].text or "")
	end
	f.league:SetText(UI.view == "league" and L.WEEK_VIEW or L.LEAGUE)
	local officerNow = ns.IAmOfficer()
	local _, inGuild = ns.Scope()
	f.addGoal:SetShown(officerNow)
	f.publish:SetShown(officerNow)
	f.publish:SetText(L.PUBLISH:format(#ns.Drafts()))
	f.publish:SetEnabled(#ns.Drafts() > 0)
	f.review:SetShown(officerNow)
	f.review:SetText(L.REVIEW_BTN:format(#ns.Suggestions()))
	f.review:SetEnabled(#ns.Suggestions() > 0)
	f.exchange:SetShown(officerNow)
	f.suggest:SetShown(inGuild and not officerNow and not ns.IsTrial())
	if not inGuild then
		f.note:SetText(L.NO_GUILD)
	elseif ns.IsTrial() then
		f.note:SetText(L.TRIAL)
	elseif #list == 0 then
		f.note:SetText(L.NOBODY)
	else
		f.note:SetText("")
	end
	f.announce:SetShown(inGuild and lines > 0)
	f.announce:SetEnabled(true)
end

-- Export / import of the goal list: a small window with the text, "Copiar" is just selecting it.
local function buildExchange()
	local f = CreateFrame("Frame", ADDON .. "ExchangeFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(360, 300)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	f.TitleText:SetText(L.EXCHANGE)
	tinsert(UISpecialFrames, ADDON .. "ExchangeFrame")
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 12, -30)
	hint:SetPoint("TOPRIGHT", -12, -30)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(true)
	hint:SetText(L.EXCHANGE_HINT)
	local body = CreateFrame("Frame", nil, f, "ScrollingEditBoxTemplate")
	body:SetPoint("TOPLEFT", 12, -62)
	body:SetPoint("BOTTOMRIGHT", -30, 40)
	local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", body, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", body, "BOTTOMRIGHT", 4, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(body:GetScrollBox(), bar)
	f.body = body
	local import = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	import:SetSize(120, 22)
	import:SetPoint("BOTTOMRIGHT", -12, 10)
	import:SetText(L.IMPORT)
	import:SetScript("OnClick", function()
		local n = ns.ImportGoals(body:GetEditBox():GetText())
		ns.Print(n and L.IMPORTED:format(n) or L.NOT_AN_EXPORT)
		if n then
			f:Hide()
		end
	end)
	f.importButton = import
	UI.exchange = f
	return f
end

function UI.ToggleExchange()
	local f = UI.exchange or buildExchange()
	if f:IsShown() then
		f:Hide()
		return
	end
	f.body:SetText(ns.ExportGoals() or "")
	f:Show()
	f.body:GetEditBox():SetFocus()
	f.body:GetEditBox():HighlightText()
end

function UI.Toggle()
	local f = UI.frame or build()
	f:SetShown(not f:IsShown())
end

function UI.Show()
	local f = UI.frame or build()
	f:Show()
	UI.Refresh()
end

ns.On("card", UI.Refresh)
ns.On("guild", UI.Refresh)
ns.On("suggest", UI.Refresh)
