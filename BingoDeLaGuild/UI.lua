local ADDON, ns = ...
local L = ns.L
local P = Pergamino

-- The window is an open book (Libs/Pergamino): the 5x5 card is stamped on the left page, the guild, the
-- league and the officers' tools take the right page, one bookmark each. Built the first time it opens.

local CELL_W, CELL_H, GAP = 70, 68, 4
local GRID_W, GRID_H = CELL_W * 5 + GAP * 4, CELL_H * 5 + GAP * 4
local BTN_W = 176

local UI = {}
ns.UI = UI
UI.view = "week" -- "week" (the card and the guild), "league" or "officers": which bookmark is open

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

local function tabTooltip(tab)
	GameTooltip:SetOwner(tab, "ANCHOR_LEFT")
	GameTooltip:SetText(tab:GetText())
	GameTooltip:AddLine(L["TAB_" .. string.upper(tab.key) .. "_TIP"] or "", 1, 1, 1, true)
	GameTooltip:Show()
end

-- a square of the card: an ink-bordered stamp on the parchment
local function makeCell(grid, i)
	local cell = CreateFrame("Button", nil, grid)
	cell:SetSize(CELL_W, CELL_H)
	local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
	cell:SetPoint("TOPLEFT", col * (CELL_W + GAP), -row * (CELL_H + GAP))
	cell.index = i
	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints()
	cell.bg:SetColorTexture(0.23, 0.14, 0.07, 0.05)
	cell.wash = cell:CreateTexture(nil, "BORDER")
	cell.wash:SetAllPoints()
	cell.wash:SetColorTexture(P.GOLD[1], P.GOLD[2], P.GOLD[3], 0.38)
	cell.wash:Hide()
	cell.edges = {}
	for k, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local e = cell:CreateTexture(nil, "ARTWORK")
		e:SetColorTexture(P.INK[1], P.INK[2], P.INK[3], 0.45)
		if side == "TOP" or side == "BOTTOM" then
			e:SetPoint(side .. "LEFT")
			e:SetPoint(side .. "RIGHT")
			e:SetHeight(1)
		else
			e:SetPoint("TOP" .. side)
			e:SetPoint("BOTTOM" .. side)
			e:SetWidth(1)
		end
		cell.edges[k] = e
	end
	local hl = cell:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(0.23, 0.14, 0.07, 0.08)
	cell.text = P.Label(cell, "", "small", "CENTER")
	cell.text:SetPoint("TOPLEFT", 4, -5)
	cell.text:SetPoint("BOTTOMRIGHT", -4, 14)
	cell.text:SetJustifyV("MIDDLE")
	cell.text:SetWordWrap(true)
	cell.progress = P.Label(cell, "", "muted", "CENTER")
	cell.progress:SetPoint("BOTTOM", 0, 3)
	cell.tick = cell:CreateTexture(nil, "OVERLAY")
	cell.tick:SetSize(16, 16)
	cell.tick:SetPoint("BOTTOMRIGHT", -3, 3)
	cell.tick:SetTexture(P.MEDIA .. "check")
	cell.tick:SetTexCoord(0.5, 1, 0, 1)
	cell.tick:Hide()
	cell.seal = cell:CreateTexture(nil, "ARTWORK", nil, 1)
	cell.seal:SetSize(34, 34)
	cell.seal:SetPoint("CENTER", 0, 6)
	cell.seal:SetTexture(P.MEDIA .. "seal")
	cell.seal:Hide()
	cell:SetScript("OnClick", function(self)
		if self.goalID ~= "free" and ns.Toggle(self.goalID) then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	end)
	cell:SetScript("OnEnter", cellTooltip)
	cell:SetScript("OnLeave", GameTooltip_Hide)
	return cell
end

-- how a square looks: todo, done, in a completed line, or the free one
local function stamp(cell, state)
	local ink, gold, crimson = P.INK, P.GOLD, P.CRIMSON
	cell.wash:SetShown(state == "done" or state == "line")
	cell.tick:SetShown(state == "done" or state == "line")
	cell.seal:SetShown(state == "free")
	if state == "line" then
		cell.wash:SetColorTexture(gold[1], gold[2], gold[3], 0.6)
	else
		cell.wash:SetColorTexture(gold[1], gold[2], gold[3], 0.38)
	end
	local c, a = ink, 0.45
	if state == "line" then
		c, a = crimson, 0.9
	elseif state == "done" then
		c, a = P.GOLD_DEEP, 0.9
	end
	for _, e in ipairs(cell.edges) do
		e:SetColorTexture(c[1], c[2], c[3], a)
	end
	if state == "free" then
		cell.text:ClearAllPoints()
		cell.text:SetPoint("BOTTOMLEFT", 2, 4)
		cell.text:SetPoint("BOTTOMRIGHT", -2, 4)
	else
		cell.text:ClearAllPoints()
		cell.text:SetPoint("TOPLEFT", 4, -5)
		cell.text:SetPoint("BOTTOMRIGHT", -4, 14)
	end
end

local function guildRow(row, item)
	if not row.name then
		row.name = P.Label(row, "", "body")
		row.name:SetPoint("LEFT", 6, 0)
		row.name:SetPoint("RIGHT", -110, 0)
		row.count = P.Label(row, "", "strong", "RIGHT")
		row.count:SetPoint("RIGHT", -6, 0)
		row.tag = P.Tag(row, "", "achievement")
		row.tag:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
	end
	row.name:SetText(item.name)
	row.count:SetText(item.right or "")
	if item.lines and item.lines > 0 then
		row.tag:Set(L.BINGO, "achievement")
		row.tag:Show()
	else
		row.tag:Hide()
	end
end

local function draftRow(row, item)
	if not row.name then
		row.name = P.Label(row, "", "body")
		row.name:SetPoint("LEFT", 6, 0)
		row.name:SetPoint("RIGHT", -6, 0)
	end
	row.name:SetText(item.text)
end

local function build()
	local FRAME = ADDON .. "Frame"
	local f = P.Book(FRAME, { title = L.TITLE, width = 860, height = 540 })
	-- clicking the book brings the whole of it over any other book that is open (their seals showed through)
	f:SetToplevel(true)
	UI.frame = f
	f.TitleText = f.title -- as the old frame had it
	for _, key in ipairs({ "carton", "liga", "oficiales" }) do
		local tab = f:AddTab(key, L["TAB_" .. string.upper(key)])
		tab.textKey = "TAB_" .. string.upper(key)
		tab:SetScript("OnEnter", tabTooltip)
		tab:SetScript("OnLeave", GameTooltip_Hide)
	end
	f.OnTab = function(key)
		UI.view = key == "liga" and "league" or key == "oficiales" and "officers" or "week"
		UI.Refresh()
	end
	f.OnMoved = function(point, _, relPoint, x, y)
		ns.db.settings.point = { point, relPoint, x, y }
	end

	-- the left page: the card, on every bookmark
	local left = f.left
	f.week = P.Label(left, "", "heading")
	f.week:SetPoint("TOPLEFT", 0, 0)
	f.week:SetPoint("RIGHT", -90, 0)
	f.week:SetWordWrap(false)
	f.status = P.Label(left, "", "big", "RIGHT")
	f.status:SetPoint("TOPRIGHT", 0, 2)
	local grid = CreateFrame("Frame", nil, left)
	grid:SetPoint("TOP", 0, -30)
	grid:SetSize(GRID_W, GRID_H)
	f.grid = grid
	UI.cells = {}
	for i = 1, 25 do
		UI.cells[i] = makeCell(grid, i)
	end
	f.by = P.Label(left, "", "muted")
	f.by:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -10)
	f.by:SetPoint("RIGHT")
	f.by:SetWordWrap(true)
	f.hint = P.Label(left, L.CARD_HINT, "muted")
	f.hint:SetPoint("BOTTOMLEFT", 0, 0)
	f.hint:SetPoint("RIGHT")
	f.hint:SetWordWrap(true)

	-- right page, "Cartón": the guild this week
	local week = f:AddPage("carton")
	local r = week.right
	f.head = P.Label(r, L.GUILD, "heading")
	f.head:SetPoint("TOPLEFT")
	local rule = P.Rule(r)
	rule:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -6)
	rule:SetPoint("RIGHT")
	f.guildRule = rule
	f.guild = P.List(r, 24, guildRow)
	f.guild.box:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6)
	f.guild.box:SetPoint("RIGHT", -14, 0)
	f.guild.box:SetHeight(300)
	-- the note (no guild, nobody yet) reads under the heading when the list is empty, under the list otherwise
	f.note = P.Label(r, "", "italic")
	f.note:SetPoint("TOPLEFT", f.guild.box, "BOTTOMLEFT", 0, -10)
	f.note:SetPoint("RIGHT")
	f.note:SetWordWrap(true)
	f.announce = P.Button(r, L.ANNOUNCE, BTN_W, function(self)
		-- only ever from this click: the addon never writes in chat by itself
		C_ChatInfo.SendChatMessage(L.ANNOUNCE_TEXT:format(ns.CountMarks(ns.Marks())), "GUILD")
		self:Disable()
	end)
	f.announce:SetPoint("BOTTOMLEFT")
	-- anyone in the guild proposes a goal to the officers
	f.suggest = P.Button(r, L.SUGGEST, BTN_W, function()
		StaticPopup_Show("BINGODELAGUILD_SUGGEST", L.SUGGEST_PROMPT)
	end)
	f.suggest:SetPoint("BOTTOMRIGHT")

	-- right page, "Liga": the last weeks added up
	local league = f:AddPage("liga")
	r = league.right
	f.leagueHead = P.Label(r, L.LEAGUE_HEAD, "heading")
	f.leagueHead:SetPoint("TOPLEFT")
	rule = P.Rule(r)
	rule:SetPoint("TOPLEFT", f.leagueHead, "BOTTOMLEFT", 0, -6)
	rule:SetPoint("RIGHT")
	f.leagueList = P.List(r, 24, guildRow)
	f.leagueList.box:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6)
	f.leagueList.box:SetPoint("RIGHT", -14, 0)
	f.leagueList.box:SetHeight(340)
	f.leagueNote = P.Label(r, L.LEAGUE_HINT, "muted")
	f.leagueNote:SetPoint("TOPLEFT", f.leagueList.box, "BOTTOMLEFT", 0, -10)
	f.leagueNote:SetPoint("RIGHT")
	f.leagueNote:SetWordWrap(true)
	f.league = f.tabs.liga -- the old button's name, for whoever looks for it

	-- right page, "Oficiales": this week's goals, the suggestions and the exchange
	local officers = f:AddPage("oficiales")
	r = officers.right
	f.officersHead = P.Label(r, L.OFFICERS_HEAD, "heading")
	f.officersHead:SetPoint("TOPLEFT")
	rule = P.Rule(r)
	rule:SetPoint("TOPLEFT", f.officersHead, "BOTTOMLEFT", 0, -6)
	rule:SetPoint("RIGHT")
	f.officersHint = P.Label(r, L.OFFICERS_HINT, "muted")
	f.officersHint:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6)
	f.officersHint:SetPoint("RIGHT")
	f.officersHint:SetWordWrap(true)
	f.drafts = P.List(r, 22, draftRow, function(_, button)
		if button == "RightButton" then
			ns.ClearDrafts()
		end
	end)
	f.drafts.box:SetPoint("TOPLEFT", f.officersHint, "BOTTOMLEFT", 0, -8)
	f.drafts.box:SetPoint("RIGHT", -14, 0)
	f.drafts.box:SetHeight(210)
	f.draftsNote = P.Label(r, "", "italic")
	f.draftsNote:SetPoint("TOPLEFT", f.drafts.box, "BOTTOMLEFT", 0, -8)
	f.draftsNote:SetPoint("RIGHT")
	f.draftsNote:SetWordWrap(true)
	f.addGoal = P.Button(r, L.ADD_GOAL, BTN_W, function()
		StaticPopup_Show("BINGODELAGUILD_GOAL", L.GOAL_PROMPT)
	end)
	f.addGoal:SetPoint("BOTTOMLEFT", 0, 36)
	f.publish = P.Button(r, "", BTN_W, function()
		ns.Publish()
	end)
	f.publish:SetPoint("BOTTOMRIGHT", 0, 36)
	f.review = P.Button(r, "", BTN_W, UI.ReviewNext)
	f.review:SetPoint("BOTTOMLEFT")
	f.exchange = P.Button(r, L.EXCHANGE, BTN_W, function()
		UI.ToggleExchange()
	end)
	f.exchange:SetPoint("BOTTOMRIGHT")

	f:HookScript("OnShow", UI.Refresh)
	local p = ns.db and ns.db.settings.point
	if p then
		f:ClearAllPoints()
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	UI.Relabel()
	return f
end

-- Every fixed text of the window, so a language change can rewrite it.
function UI.Relabel()
	local f = UI.frame
	if not f then
		return
	end
	f:SetTitle(L.TITLE)
	for key, tab in pairs(f.tabs) do
		tab:SetText(L[tab.textKey] or key)
	end
	f.hint:SetText(L.CARD_HINT)
	f.head:SetText(L.GUILD)
	f.announce:SetText(L.ANNOUNCE)
	f.suggest:SetText(L.SUGGEST)
	f.leagueHead:SetText(L.LEAGUE_HEAD)
	f.leagueNote:SetText(L.LEAGUE_HINT)
	f.officersHead:SetText(L.OFFICERS_HEAD)
	f.officersHint:SetText(L.OFFICERS_HINT)
	f.addGoal:SetText(L.ADD_GOAL)
	f.exchange:SetText(L.EXCHANGE)
	if UI.exchange then
		UI.exchange:SetTitle(L.EXCHANGE)
		UI.exchange.hint:SetText(L.EXCHANGE_HINT)
		UI.exchange.importButton:SetText(L.IMPORT)
	end
end

function UI.Refresh()
	local f = UI.frame
	if not f or not f:IsShown() then
		return
	end
	local _, resetAt = ns.Week()
	local officer = ns.OfficerCard()
	f.week:SetText(L.WEEK_UNTIL:format(date("%d/%m %H:%M", resetAt)))
	f.by:SetText(officer and L.CARD_BY:format(officer.by) or "")
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
			stamp(cell, inLine[i] and "line" or "free")
		else
			local g = ns.Goal(id)
			cell.text:SetText(ns.GoalText(g))
			if g.count and g.need > 1 and not done then
				cell.progress:SetText(ns.Progress(g) .. "/" .. g.need)
			else
				cell.progress:SetText("")
			end
			stamp(cell, inLine[i] and "line" or done and "done" or "todo")
		end
	end

	-- the guild: this week's cards (same card as yours)
	local list = {}
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
		e.right = L.MARKED:format(e.marks)
	end
	f.guild:SetData(list, true)
	UI.rows = list

	-- the league of the last weeks
	local table_ = {}
	for _, e in ipairs(ns.League()) do
		table_[#table_ + 1] = { name = e.name, right = e.points == 1 and L.POINTS_1 or L.POINTS:format(e.points) }
	end
	f.leagueList:SetData(table_, true)

	local officerNow = ns.IAmOfficer()
	local _, inGuild = ns.Scope()
	-- the officers' bookmark exists only for officers (it is the last one, so hiding it leaves no gap)
	f.tabs.oficiales:SetShown(officerNow)
	if not officerNow and f.selected == "oficiales" then
		f:SelectTab("carton")
		return
	end
	local drafts = {}
	for i, text in ipairs(ns.Drafts()) do
		drafts[i] = { text = i .. ". " .. text }
	end
	f.drafts:SetData(drafts, true)
	f.draftsNote:SetText(#drafts == 0 and L.NO_DRAFTS or L.DRAFTS_RIGHT_CLICK)
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
		f.note:SetText(L.NO_GUILD .. "\n\n" .. L.NO_GUILD_HINT)
	elseif ns.IsTrial() then
		f.note:SetText(L.TRIAL)
	elseif #list == 0 then
		f.note:SetText(L.NOBODY .. "\n\n" .. L.NOBODY_HINT)
	else
		f.note:SetText("")
	end
	-- an empty list makes no page: the note takes its place right under the heading
	local empty = #list == 0
	f.guild.box:SetShown(not empty)
	f.note:ClearAllPoints()
	if empty then
		f.note:SetPoint("TOPLEFT", f.guildRule, "BOTTOMLEFT", 0, -12)
	else
		f.note:SetPoint("TOPLEFT", f.guild.box, "BOTTOMLEFT", 0, -10)
	end
	f.note:SetPoint("RIGHT")
	f.announce:SetShown(inGuild and lines > 0)
	f.announce:SetEnabled(true)
end

-- Export / import of the goal list: a parchment card with the text; "copy" is just selecting it.
local function buildExchange()
	local f = P.Card(ADDON .. "ExchangeFrame", 420, 340, L.EXCHANGE)
	f.hint = P.Label(f.body, L.EXCHANGE_HINT, "muted")
	f.hint:SetPoint("TOPLEFT")
	f.hint:SetPoint("RIGHT")
	f.hint:SetWordWrap(true)
	local area = P.TextArea(f.body)
	area:SetPoint("TOPLEFT", f.hint, "BOTTOMLEFT", 0, -8)
	area:SetPoint("BOTTOMRIGHT", 0, 34)
	f.area = area
	f.body = area.box -- the ScrollingEditBox, as before
	local import = P.Button(f, L.IMPORT, 120, function()
		local n = ns.ImportGoals(f.body:GetEditBox():GetText())
		ns.Print(n and (n == 1 and L.IMPORTED_1 or L.IMPORTED:format(n)) or L.NOT_AN_EXPORT)
		if n then
			f:Hide()
		end
	end)
	import:SetPoint("BOTTOMRIGHT", -20, 20)
	f.importButton = import
	function f:SetTitle(text)
		self.title:SetText(text)
	end
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
	if f:IsShown() then
		f:Hide()
		return
	end
	f:Show()
	f:SelectTab(UI.view == "league" and "liga" or UI.view == "officers" and "oficiales" or "carton")
end

function UI.Show()
	local f = UI.frame or build()
	f:Show()
	f:SelectTab(UI.view == "league" and "liga" or UI.view == "officers" and "oficiales" or "carton")
	UI.Refresh()
end

ns.On("card", UI.Refresh)
ns.On("guild", UI.Refresh)
ns.On("suggest", UI.Refresh)
ns.On("language", function()
	UI.Relabel()
	UI.Refresh()
end)
