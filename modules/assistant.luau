--!nonstrict
return {
Name = "assistant", API = 1,
Requires = {"chat-common"},
Install = function(context)
	local ASSETS_FOLDER = context.ASSETS_FOLDER
	local Corner = context.Corner
	local EnsureAssetsFolder = context.EnsureAssetsFolder
	local HttpService = context.HttpService
	local LocalPlayer = context.LocalPlayer
	local MeasureText = context.MeasureText
	local NullUI = context.NullUI
	local Players = context.Players
	local ResolveIcon = context.ResolveIcon
	local SafeConfigName = context.SafeConfigName
	local Stroke = context.Stroke
	local Tab = context.Tab
	local Tween = context.Tween
	local TweenService = context.TweenService
	local Window = context.Window
	local Z = context.Z
	local fn_isfile = context.fn_isfile
	local fn_readfile = context.fn_readfile
	local fn_writefile = context.fn_writefile
	local hasFn = context.hasFn
	local CreateChatComposer, CreateChatMessages, BindChatAutoscroll, ChatHeaderButton = context.Shared.CreateChatComposer, context.Shared.CreateChatMessages, context.Shared.BindChatAutoscroll, context.Shared.ChatHeaderButton
local CHAT_CODE_FONT = "rbxasset://fonts/families/RobotoMono.json"

local function EscapeRichText(text)
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	return text
end

local function MarkdownToRichText(text)
	text = EscapeRichText(text)

	text = text:gsub("`([^`\n]+)`", "<font family=\"" .. CHAT_CODE_FONT .. "\">%1</font>")

	text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	text = text:gsub("__(.-)__", "<b>%1</b>")

	text = text:gsub("%*([^%s*][^*]-)%*", "<i>%1</i>")
	text = text:gsub("_([^%s_][^_]-)_", "<i>%1</i>")

	return text
end

local function SplitMessageSegments(text)
	local segments = {}
	local pos = 1
	while true do
		local s, e, lang, code = text:find("```(%w*)\n?(.-)```", pos)
		if not s then
			local rest = text:sub(pos)
			if rest ~= "" then table.insert(segments, { kind = "text", content = rest }) end
			break
		end
		if s > pos then
			local before = text:sub(pos, s - 1)
			if before:match("%S") then
				table.insert(segments, { kind = "text", content = before })
			end
		end
		code = code:gsub("^%s+", ""):gsub("%s+$", "")
		table.insert(segments, { kind = "code", lang = lang ~= "" and lang or "lua", content = code })
		pos = e + 1
	end
	if #segments == 0 then
		table.insert(segments, { kind = "text", content = text })
	end
	return segments
end

local LUA_KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true,
	["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true, ["continue"] = true,
}

local function HighlightLua(code)
	local out = {}
	local n = #code
	local i = 1

	while i <= n do
		local c = code:sub(i, i)

		if code:sub(i, i + 3) == "--[[" then
			local closeEnd = select(2, code:find("%]%]", i + 4))
			local stop = closeEnd or n
			out[#out + 1] = "<font color=\"#6A9955\">" .. code:sub(i, stop) .. "</font>"
			i = stop + 1
		elseif code:sub(i, i + 1) == "--" then
			local nl = code:find("\n", i, true)
			local stop = (nl or (n + 1)) - 1
			out[#out + 1] = "<font color=\"#6A9955\">" .. code:sub(i, stop) .. "</font>"
			i = stop + 1
		elseif c == '"' or c == "'" then
			local quote = c
			local j = i + 1
			while j <= n do
				local jc = code:sub(j, j)
				if jc == "\\" then
					j = j + 2
				elseif jc == quote or jc == "\n" then
					break
				else
					j = j + 1
				end
			end
			j = math.min(j, n)
			out[#out + 1] = "<font color=\"#CE9178\">" .. code:sub(i, j) .. "</font>"
			i = j + 1
		elseif c:match("%a") or c == "_" then
			local j = i
			while j <= n and code:sub(j, j):match("[%w_]") do j = j + 1 end
			local word = code:sub(i, j - 1)
			out[#out + 1] = LUA_KEYWORDS[word] and ("<font color=\"#C586C0\">" .. word .. "</font>") or word
			i = j
		elseif c:match("%d") then
			local j = i
			while j <= n and code:sub(j, j):match("[%d%.]") do j = j + 1 end
			out[#out + 1] = "<font color=\"#B5CEA8\">" .. code:sub(i, j - 1) .. "</font>"
			i = j
		else
			out[#out + 1] = c
			i = i + 1
		end
	end

	return table.concat(out)
end

function Window:_BuildDefaultChatTools()
	local windowSelf = self

	return {
		{
			Name = "list_ui_elements",
			Description = "Lists every UI element that has a Flag, with its kind and current value.",
			Parameters = { type = "object", properties = {}, required = {} },
			Handler = function()
				return NullUI:ListUIElements()
			end,
		},
		{
			Name = "set_ui_element_value",
			Description = "Sets a UI element's value by its flag name. Use list_ui_elements first to find valid flags.",
			Parameters = {
				type = "object",
				properties = {
					flag  = { type = "string", description = "The Flag of the UI element to change." },
					value = { description = "The new value: true/false for a Toggle, a number for a Slider, a string for a Textbox/Dropdown." },
				},
				required = { "flag", "value" },
			},
			Handler = function(args)
				local ok, err = NullUI:SetUIElementValue(args.flag, args.value)
				if not ok then error(err, 0) end
				return true
			end,
		},
		{
			Name = "select_tab",
			Description = "Switches the panel to one of its top-level sidebar tabs.",
			Parameters = {
				type = "object",
				properties = {
					tab = { type = "string", description = "The tab's name." },
				},
				required = { "tab" },
			},
			Handler = function(args)
				local tabObj = windowSelf:SelectTab(args.tab)
				if not tabObj then error("No tab named '" .. tostring(args.tab) .. "'", 0) end
				return "Switched to " .. tabObj.Name
			end,
		},
		{
			Name = "select_subtab",
			Description = "Switches to a sub-tab nested under one of the top-level tabs. Selects the "
				.. "parent tab first automatically -- no need to call select_tab beforehand.",
			Parameters = {
				type = "object",
				properties = {
					tab    = { type = "string", description = "The top-level tab that contains the sub-tab." },
					subtab = { type = "string", description = "The sub-tab's name." },
				},
				required = { "tab", "subtab" },
			},
			Handler = function(args)
				local tabObj = windowSelf:SelectTab(args.tab)
				if not tabObj then error("No tab named '" .. tostring(args.tab) .. "'", 0) end
				local sub = tabObj:SelectSubTabByName(args.subtab)
				if not sub then
					error("No sub-tab named '" .. tostring(args.subtab) .. "' under " .. tabObj.Name, 0)
				end
				return "Switched to " .. tabObj.Name .. " > " .. sub.Name
			end,
		},
		{
			Name = "find_and_highlight_element",
			Description = "Finds a UI element (button, toggle, card, slider, etc.) by its visible label, "
				.. "jumps to whichever tab or sub-tab it lives on, scrolls to it, and flashes a highlight "
				.. "on it -- the same thing Ctrl+K search does when you click a result.",
			Parameters = {
				type = "object",
				properties = {
					query = { type = "string", description = "The element's visible text. Partial matches are fine." },
				},
				required = { "query" },
			},
			Handler = function(args)
				local ok, titleOrErr = windowSelf:JumpToElement(args.query)
				if not ok then error(titleOrErr, 0) end
				return "Highlighted: " .. titleOrErr
			end,
		},
	}
end

function Window:_BuildDefaultSystemPrompt()
	local names = {}
	for _, t in ipairs(self._tabs) do
		if not t.Hidden then table.insert(names, t.Name) end
	end

	return "You are a helpful assistant embedded in a Roblox UI panel built with NullUI. Your tools "
		.. "only affect THIS PANEL -- they inspect/adjust the panel's own toggles/sliders/etc, switch "
		.. "between its top-level tabs (" .. table.concat(names, ", ") .. "), switch to a specific "
		.. "sub-tab within one of those, and jump to/highlight a specific UI element on the panel by "
		.. "its visible label. Only use select_tab, select_subtab, or find_and_highlight_element when "
		.. "the user is asking to be taken somewhere IN THIS PANEL, or to interact with a control "
		.. "that's actually on it. If the user asks you to write a script, explain something, or "
		.. "anything else that isn't about navigating this panel, just answer directly in chat -- do "
		.. "not call a tool just because the message happens to mention a word that sounds like a "
		.. "setting. When you write a Luau script for the user, put it in a normal ```lua fenced block "
		.. "-- the panel automatically adds a Run button to it that the user can click themselves, so "
		.. "you don't need to explain how to run it or tell them you can't execute code; you're just "
		.. "not the one who decides to run it -- they click Run after reading it. Keep answers short "
		.. "and to the point. None of your tools execute anything outside this panel, and you have no "
		.. "way to trigger the Run button yourself."
end

function Window:AddChatPanel(opts)
	opts = opts or {}
	opts.Tools = opts.Tools or self:_BuildDefaultChatTools()
	local jan = self._janitor

	local tabObj = self:AddTab({
		Name   = opts.Name or "Assistant",
		Icon   = opts.Icon or "bot",
		Hidden = true,
	})
	tabObj._page.Visible = false

	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end

	local toolByName = {}
	for _, tool in ipairs(opts.Tools or {}) do
		if tool.Name then toolByName[tool.Name] = tool end
	end

	local INPUT_H = 38
	local HEADER_H = 38

	local panel = Instance.new("Frame")
	panel.Name = "ChatPanel"
	panel.BackgroundTransparency = 1
	panel.ClipsDescendants = true
	panel.Size = UDim2.fromScale(1, 1)
	panel.ZIndex = Z.Content
	panel.Parent = tabObj._group

	local BASE_Z = panel.ZIndex + 1

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = panel.ZIndex
	content.Parent = panel

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Active = true
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = BASE_Z
	header.Parent = content

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header

	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -84, 1, 0)
	titleRow.ZIndex = BASE_Z + 1
	titleRow.Parent = header

	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow

	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "bot")
	titleIcon.ImageColor3 = NullUI.Theme.Text
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = BASE_Z + 2
	titleIcon.Parent = titleRow

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = opts.Title or "Assistant"
	titleLabel.TextColor3 = NullUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 16)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = BASE_Z + 2
	titleLabel.Parent = titleRow

	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(100, 22)
	controls.ZIndex = BASE_Z + 1
	controls.Parent = header

	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls

	local function headerIconButton(icon, order)
		return ChatHeaderButton(controls, BASE_Z, jan, icon, order)
	end

	local copyBtn, copyIcon = headerIconButton("copy", 1)
	local regenBtn, regenIcon = headerIconButton("refresh-cw", 2)
	local clearBtn = headerIconButton("trash-2", 3)
	local closeBtn = headerIconButton("x", 4)

	local headerDivider = Instance.new("Frame")
	headerDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	headerDivider.BackgroundTransparency = 0.94
	headerDivider.BorderSizePixel = 0
	headerDivider.Position = UDim2.fromOffset(0, HEADER_H)
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.ZIndex = BASE_Z
	headerDivider.Parent = content

	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingLeft = UDim.new(0, 14)
	contentPad.PaddingRight = UDim.new(0, 14)
	contentPad.PaddingBottom = UDim.new(0, 12)
	contentPad.Parent = content

	local inputRow, pill, inputBox, sendBtn, sendIcon = CreateChatComposer(content, INPUT_H, BASE_Z, jan, opts.Placeholder or "Ask me anything...")

	local msgScroll, msgLayout = CreateChatMessages(content, panel, HEADER_H, INPUT_H, BASE_Z, jan)

	local order = 0
	local transcript = {}

	local scrollToBottom = BindChatAutoscroll(msgScroll, jan)

	local AVATAR = 26

	local function addBubble(text, role)
		local isUser = role == "user"
		order = order + 1

		text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n\n\n+", "\n\n")

		local row = Instance.new("Frame")
		row.Name = "MessageRow"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll

		local rowScale = Instance.new("UIScale")
		rowScale.Scale = 0.92
		rowScale.Parent = row

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = isUser and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row

		local avatarFinalTransparency = isUser and 0.85 or 0.82
		local avatar = Instance.new("Frame")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = isUser and Color3.new(1, 1, 1) or NullUI.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = isUser and 2 or 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)

		local avatarIcon
		if isUser then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.ImageTransparency = 1
			img.ScaleType = Enum.ScaleType.Crop
			img.Size = UDim2.fromScale(1, 1)
			img.ZIndex = BASE_Z + 3
			img.Parent = avatar
			Corner(img, AVATAR / 2)
			avatarIcon = img
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					LocalPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
				if ok and content and img.Parent then
					img.Image = content
				end
			end)
		else
			local botIcon = Instance.new("ImageLabel")
			botIcon.BackgroundTransparency = 1
			botIcon.ImageTransparency = 1
			botIcon.Image = ResolveIcon("bot")
			botIcon.ImageColor3 = NullUI.Theme.Accent
			botIcon.Size = UDim2.fromOffset(14, 14)
			botIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			botIcon.Position = UDim2.fromScale(0.5, 0.5)
			botIcon.ZIndex = BASE_Z + 3
			botIcon.Parent = avatar
			avatarIcon = botIcon
		end

		local segments = SplitMessageSegments(text)
		local hasCode = false
		for _, seg in ipairs(segments) do
			if seg.kind == "code" then hasCode = true end
		end

		local H_PAD, V_PAD = 10, 8
		local BUBBLE_MAX_WIDTH = hasCode and 380 or 260
		local bubbleWidth
		if hasCode then
			bubbleWidth = BUBBLE_MAX_WIDTH
		else
			local naturalW = MeasureText(segments[1].content, 13, 10000)
			bubbleWidth = math.min(naturalW, BUBBLE_MAX_WIDTH - H_PAD * 2) + H_PAD * 2
		end
		if msgScroll.AbsoluteSize.X > 0 then
			bubbleWidth = math.min(bubbleWidth, math.max(200, msgScroll.AbsoluteSize.X - 20))
		end

		local bubbleFinalTransparency = isUser and 0.72 or 0.9
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.BackgroundColor3 = isUser and NullUI.Theme.Accent or Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
		bubble.LayoutOrder = isUser and 1 or 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local strokeFinalTransparency = isUser and 0.8 or 0.9
		local bubbleStroke = Stroke(bubble, Color3.new(1, 1, 1), 1, 1)

		local bubblePad = Instance.new("UIPadding")
		bubblePad.PaddingTop = UDim.new(0, V_PAD)
		bubblePad.PaddingBottom = UDim.new(0, V_PAD)
		bubblePad.PaddingLeft = UDim.new(0, H_PAD)
		bubblePad.PaddingRight = UDim.new(0, H_PAD)
		bubblePad.Parent = bubble

		local bubbleLayout = Instance.new("UIListLayout")
		bubbleLayout.FillDirection = Enum.FillDirection.Vertical
		bubbleLayout.Padding = UDim.new(0, 8)
		bubbleLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bubbleLayout.Parent = bubble

		Tween(avatar, { BackgroundTransparency = avatarFinalTransparency }, 0.16)
		Tween(avatarIcon, { ImageTransparency = 0 }, 0.16)
		Tween(bubble, { BackgroundTransparency = bubbleFinalTransparency }, 0.16)
		Tween(bubbleStroke, { Transparency = strokeFinalTransparency }, 0.16)
		Tween(rowScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		local TYPE_START_DELAY = 0.08
		local maxTypeDuration = 0

		for i, seg in ipairs(segments) do
			if seg.kind == "code" then
				local card = Instance.new("Frame")
				card.Name = "CodeBlock"
				card.BackgroundColor3 = NullUI.Theme.Background
				card.BackgroundTransparency = 0.1
				card.BorderSizePixel = 0
				card.ClipsDescendants = true
				card.AutomaticSize = Enum.AutomaticSize.Y
				card.Size = UDim2.new(1, 0, 0, 0)
				card.LayoutOrder = i
				card.ZIndex = BASE_Z + 3
				card.Parent = bubble
				Corner(card, 8)
				Stroke(card, Color3.new(1, 1, 1), 1, 0.92)

				local cardLayout = Instance.new("UIListLayout")
				cardLayout.FillDirection = Enum.FillDirection.Vertical
				cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
				cardLayout.Parent = card

				local header = Instance.new("Frame")
				header.BackgroundTransparency = 1
				header.Size = UDim2.new(1, 0, 0, 24)
				header.LayoutOrder = 1
				header.ZIndex = BASE_Z + 4
				header.Parent = card

				local langLabel = Instance.new("TextLabel")
				langLabel.BackgroundTransparency = 1
				langLabel.FontFace = NullUI.Theme.FontRegular
				langLabel.Text = seg.lang
				langLabel.TextColor3 = NullUI.Theme.TextDim
				langLabel.TextSize = 11
				langLabel.TextXAlignment = Enum.TextXAlignment.Left
				langLabel.Position = UDim2.fromOffset(10, 0)
				langLabel.Size = UDim2.new(1, -70, 1, 0)
				langLabel.ZIndex = BASE_Z + 5
				langLabel.Parent = header

				local function codeHeaderButton(icon, rightOffset)
					local btn = Instance.new("TextButton")
					btn.Text = ""
					btn.AutoButtonColor = false
					btn.BackgroundColor3 = Color3.new(1, 1, 1)
					btn.BackgroundTransparency = 1
					btn.BorderSizePixel = 0
					btn.AnchorPoint = Vector2.new(1, 0.5)
					btn.Position = UDim2.new(1, -rightOffset, 0.5, 0)
					btn.Size = UDim2.fromOffset(20, 20)
					btn.ZIndex = BASE_Z + 5
					btn.Parent = header
					Corner(btn, 5)

					local ic = Instance.new("ImageLabel")
					ic.BackgroundTransparency = 1
					ic.Image = ResolveIcon(icon)
					ic.ImageColor3 = NullUI.Theme.TextDim
					ic.Size = UDim2.fromOffset(12, 12)
					ic.AnchorPoint = Vector2.new(0.5, 0.5)
					ic.Position = UDim2.fromScale(0.5, 0.5)
					ic.ZIndex = BASE_Z + 6
					ic.Parent = btn

					jan:Add(btn.MouseEnter:Connect(function()
						Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
						Tween(ic, { ImageColor3 = NullUI.Theme.Text }, 0.12)
					end))
					jan:Add(btn.MouseLeave:Connect(function()
						Tween(btn, { BackgroundTransparency = 1 }, 0.12)
						Tween(ic, { ImageColor3 = NullUI.Theme.TextDim }, 0.12)
					end))

					return btn, ic
				end

				local copyBtn, copyIcon = codeHeaderButton("copy", 8)
				jan:Add(copyBtn.MouseButton1Click:Connect(function()
					local setclipboard = hasFn("setclipboard")
					if not setclipboard then return end
					pcall(setclipboard, seg.content)
					Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
					task.delay(0.4, function()
						if copyIcon.Parent then
							Tween(copyIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.15)
						end
					end)
				end))

				if opts.OnRunCode then
					local runBtn, runIcon = codeHeaderButton("play", 32)
					jan:Add(runBtn.MouseButton1Click:Connect(function()
						NullUI:Confirm({
							Title = "Run this code?",
							Text = "This runs exactly what's shown above, right now, in this game.",
							ConfirmText = "Run",
							CancelText = "Cancel",
							Danger = true,
							Window = self,
							Callback = function(confirmed)
								if not confirmed then return end
								local ok, err = pcall(opts.OnRunCode, seg.content, seg.lang)
								NullUI:Notify({
									Title = ok and "Ran" or "Run failed",
									Text = ok and "Code executed." or tostring(err),
									Type = ok and "success" or "error",
									Duration = 3,
								})
							end,
						})
					end))
				end

				local headerDivider = Instance.new("Frame")
				headerDivider.BackgroundColor3 = Color3.new(1, 1, 1)
				headerDivider.BackgroundTransparency = 0.92
				headerDivider.BorderSizePixel = 0
				headerDivider.Size = UDim2.new(1, 0, 0, 1)
				headerDivider.LayoutOrder = 2
				headerDivider.ZIndex = BASE_Z + 4
				headerDivider.Parent = card

				local codeContainer = Instance.new("Frame")
				codeContainer.BackgroundTransparency = 1
				codeContainer.AutomaticSize = Enum.AutomaticSize.Y
				codeContainer.Size = UDim2.new(1, 0, 0, 0)
				codeContainer.LayoutOrder = 3
				codeContainer.ZIndex = BASE_Z + 4
				codeContainer.Parent = card

				local codePad = Instance.new("UIPadding")
				codePad.PaddingTop = UDim.new(0, 8)
				codePad.PaddingBottom = UDim.new(0, 8)
				codePad.PaddingLeft = UDim.new(0, 10)
				codePad.PaddingRight = UDim.new(0, 10)
				codePad.Parent = codeContainer

				local codeLabel = Instance.new("TextLabel")
				codeLabel.BackgroundTransparency = 1
				codeLabel.FontFace = Font.new(CHAT_CODE_FONT, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
				codeLabel.RichText = true
				codeLabel.Text = HighlightLua(EscapeRichText(seg.content))
				codeLabel.TextColor3 = NullUI.Theme.Text
				codeLabel.TextSize = 12
				codeLabel.TextWrapped = true
				codeLabel.TextXAlignment = Enum.TextXAlignment.Left
				codeLabel.TextYAlignment = Enum.TextYAlignment.Top
				codeLabel.LineHeight = 1.3
				codeLabel.AutomaticSize = Enum.AutomaticSize.Y
				codeLabel.Size = UDim2.new(1, 0, 0, 16)
				codeLabel.ZIndex = BASE_Z + 5
				codeLabel.Parent = codeContainer
			else
				local label = Instance.new("TextLabel")
				label.Name = "Prose"
				label.BackgroundTransparency = 1
				label.FontFace = NullUI.Theme.FontRegular
				label.RichText = true
				label.Text = MarkdownToRichText(seg.content)
				label.TextColor3 = NullUI.Theme.Text
				label.TextTransparency = 1
				label.TextSize = 13
				label.TextWrapped = true
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Top
				label.LineHeight = 1.3
				label.AutomaticSize = Enum.AutomaticSize.Y
				label.Size = UDim2.new(1, 0, 0, 16)
				label.LayoutOrder = i
				label.ZIndex = BASE_Z + 3

				label.MaxVisibleGraphemes = 0
				label.Parent = bubble

				Tween(label, { TextTransparency = 0 }, 0.16)

				local graphemeCount = utf8.len(seg.content) or #seg.content
				local typeDuration = math.clamp(graphemeCount * 0.014, 0.12, 1.6)
				maxTypeDuration = math.max(maxTypeDuration, typeDuration)
				task.delay(TYPE_START_DELAY, function()
					if label and label.Parent then
						TweenService:Create(
							label,
							TweenInfo.new(typeDuration, Enum.EasingStyle.Linear),
							{ MaxVisibleGraphemes = graphemeCount }
						):Play()
					end
				end)
			end
		end

		scrollToBottom()
		table.insert(transcript, (isUser and "You" or "Assistant") .. ": " .. text)

		return TYPE_START_DELAY + maxTypeDuration
	end

	local bumpTypingToBottom

	local function addToolLine(name)
		order = order + 1
		local row = Instance.new("Frame")
		row.Name = "ToolCall"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 18)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.Parent = row

		local toolIcon = Instance.new("ImageLabel")
		toolIcon.BackgroundTransparency = 1
		toolIcon.Image = ResolveIcon("wrench")
		toolIcon.ImageColor3 = NullUI.Theme.Accent
		toolIcon.Size = UDim2.fromOffset(11, 11)
		toolIcon.LayoutOrder = 1
		toolIcon.ZIndex = BASE_Z + 2
		toolIcon.Parent = row

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = NullUI.Theme.FontRegular
		label.Text = "Called tool: " .. tostring(name)
		label.TextColor3 = NullUI.Theme.TextDim
		label.TextSize = 11
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 14)
		label.LayoutOrder = 2
		label.ZIndex = BASE_Z + 2
		label.Parent = row

		scrollToBottom()
		table.insert(transcript, "[Called tool: " .. tostring(name) .. "]")
		if bumpTypingToBottom then bumpTypingToBottom() end
	end

	local typingRow, typingTweens, typingActive = nil, nil, false

	local function destroyTypingRow()
		if not typingRow then return end
		for _, tw in ipairs(typingTweens) do tw:Cancel() end
		local row = typingRow
		typingRow, typingTweens = nil, nil
		row:Destroy()
	end

	local function buildTypingRow()
		order = order + 1

		local row = Instance.new("Frame")
		row.Name = "TypingRow"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row

		local avatar = Instance.new("Frame")
		avatar.BackgroundColor3 = NullUI.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)

		local botIcon = Instance.new("ImageLabel")
		botIcon.BackgroundTransparency = 1
		botIcon.ImageTransparency = 1
		botIcon.Image = ResolveIcon("bot")
		botIcon.ImageColor3 = NullUI.Theme.Accent
		botIcon.Size = UDim2.fromOffset(14, 14)
		botIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		botIcon.Position = UDim2.fromScale(0.5, 0.5)
		botIcon.ZIndex = BASE_Z + 3
		botIcon.Parent = avatar

		local bubble = Instance.new("Frame")
		bubble.BackgroundColor3 = Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.Size = UDim2.fromOffset(38, AVATAR)
		bubble.LayoutOrder = 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local bubbleStroke = Stroke(bubble, Color3.new(1, 1, 1), 1, 1)

		local tweens = {}
		for i = 1, 3 do
			local baseX = 10 + (i - 1) * 9
			local dot = Instance.new("Frame")
			dot.BackgroundColor3 = NullUI.Theme.TextDim
			dot.BackgroundTransparency = 1
			dot.BorderSizePixel = 0
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.new(0, baseX, 0.5, 0)
			dot.Size = UDim2.fromOffset(4, 4)
			dot.ZIndex = BASE_Z + 3
			dot.Parent = bubble
			Corner(dot, 2)
			Tween(dot, { BackgroundTransparency = 0 }, 0.15)

			tweens[i] = TweenService:Create(
				dot,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i - 1) * 0.15),
				{ Position = UDim2.new(0, baseX, 0.5, -3) }
			)
			tweens[i]:Play()
		end

		Tween(avatar, { BackgroundTransparency = 0.82 }, 0.15)
		Tween(botIcon, { ImageTransparency = 0 }, 0.15)
		Tween(bubble, { BackgroundTransparency = 0.9 }, 0.15)
		Tween(bubbleStroke, { Transparency = 0.9 }, 0.15)

		typingRow, typingTweens = row, tweens
		scrollToBottom()
	end

	local function showTyping()
		if typingRow then return end
		typingActive = true
		buildTypingRow()
	end

	function bumpTypingToBottom()
		if not typingRow then return end
		destroyTypingRow()
		buildTypingRow()
	end

	local function hideTyping()
		if not typingActive then return end
		typingActive = false
		destroyTypingRow()
	end

	local function addMessage(role, text)
		text = tostring(text or "")
		if text == "" then return end
		hideTyping()
		if role == "tool" then
			addToolLine(text)
			return nil
		end
		return addBubble(text, role)
	end

	local function handleToolCall(name, args)
		local tool = toolByName[name]
		addToolLine(name)
		if not tool or not tool.Handler then
			addMessage("assistant", "Unknown tool: " .. tostring(name))
			return nil
		end
		local ok, result = pcall(tool.Handler, args)
		if not ok then
			addMessage("assistant", "Tool error: " .. tostring(result))
			return nil
		end
		return result
	end

	local api

	local sending = false
	local lastUserText = nil

	local function setSending(value)
		sending = value
		sendIcon.Image = ResolveIcon(value and "square" or "send")
	end

	local function trySend(overrideText)
		local text = overrideText or inputBox.Text
		if sending or text == "" then return end
		setSending(true)
		if not overrideText then inputBox.Text = "" end
		lastUserText = text
		local revealTime = addMessage("user", text)
		if opts.OnSend then
			local finished = false

			task.spawn(function()

				if revealTime and revealTime > 0 then task.wait(revealTime) end
				local ok, err = pcall(opts.OnSend, api, text)
				if not ok then
					addMessage("assistant", "Error: " .. tostring(err))
				end
				finished = true
				setSending(false)
			end)

			task.delay(opts.SendTimeout or 30, function()
				if not finished and sending then
					setSending(false)
					hideTyping()
					addMessage("assistant", "(Taking too long -- you can try sending again.)")
				end
			end)
		else
			setSending(false)
		end
	end

	local function tryRegenerate()
		if sending or not lastUserText then return end
		if opts.OnRegenerate then
			task.spawn(opts.OnRegenerate, api, lastUserText)
		else
			trySend(lastUserText)
		end
	end

	local lastRealTab = nil

	local function openChat()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end

	local function closeChat()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end

	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)

	local function clearChat()
		hideTyping()
		for _, child in ipairs(msgScroll:GetChildren()) do
			if child.Name == "MessageRow" or child.Name == "ToolCall" then
				child:Destroy()
			end
		end
		table.clear(transcript)
		if opts.OnClear then task.spawn(opts.OnClear) end
	end

	jan:Add(sendBtn.MouseButton1Click:Connect(function()
		if sending then
			if opts.OnStop then task.spawn(opts.OnStop, api) end
		else
			trySend()
		end
	end))
	jan:Add(inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then trySend() end
	end))
	jan:Add(closeBtn.MouseButton1Click:Connect(closeChat))

	jan:Add(copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard or #transcript == 0 then return end
		pcall(setclipboard, table.concat(transcript, "\n\n"))
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.15)
			end
		end)
	end))
	jan:Add(regenBtn.MouseButton1Click:Connect(function()
		if sending or not lastUserText then return end
		Tween(regenIcon, { Rotation = regenIcon.Rotation + 180 }, 0.25)
		tryRegenerate()
	end))
	jan:Add(clearBtn.MouseButton1Click:Connect(function()
		clearChat()
		lastUserText = nil
	end))

	api = {
		Instance = panel,
		Tab = tabObj,
		Open = openChat,
		Close = closeChat,
		Toggle = function()
			if self._currentTab == tabObj then closeChat() else openChat() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		AddMessage = function(_, role, text) addMessage(role, text) end,
		LogToolCall = function(_, name) addToolLine(name) end,
		HandleToolCall = function(_, name, args) return handleToolCall(name, args) end,
		ShowTyping = function() showTyping() end,
		HideTyping = function() hideTyping() end,
		IsSending = function() return sending end,
		Clear = function() clearChat() end,
		Destroy = function() panel:Destroy() end,
	}

	return api
end

function NullUI:CreateAIAssistant(opts)
	opts = opts or {}
	local providers = opts.Providers or {}
	local tools = opts.Tools or (opts.Window and opts.Window:_BuildDefaultChatTools()) or {}
	local systemPrompt = opts.SystemPrompt
		or (opts.Window and opts.Window:_BuildDefaultSystemPrompt())
		or "You are a helpful assistant."
	local maxRounds = opts.MaxRounds or 6
	local maxTokens = opts.MaxTokens or 2048
	local httpRequest = (syn and syn.request) or http_request or request

	local function toOpenAITools()
		local out = {}
		for _, tool in ipairs(tools) do
			table.insert(out, {
				type = "function",
				["function"] = {
					name        = tool.Name,
					description = tool.Description,
					parameters  = tool.Parameters,
				},
			})
		end
		return out
	end

	local persistPath = nil
	if opts.Persist then
		persistPath = ASSETS_FOLDER .. "/" .. SafeConfigName(tostring(opts.Persist)) .. ".chat.json"
	end

	local function loadHistory()
		if not (persistPath and fn_isfile and fn_readfile) then return nil end
		local existsOk, exists = pcall(fn_isfile, persistPath)
		if not existsOk or not exists then return nil end
		local ok, raw = pcall(fn_readfile, persistPath)
		if not ok then return nil end
		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
		if decodeOk and type(decoded) == "table" then return decoded end
		return nil
	end

	local conversation = loadHistory() or { { role = "system", content = systemPrompt } }

	local function saveHistory()
		if not (persistPath and fn_writefile) then return end
		EnsureAssetsFolder()
		pcall(fn_writefile, persistPath, HttpService:JSONEncode(conversation))
	end

	local function callProvider(provider, messages)
		local body = HttpService:JSONEncode({
			model      = provider.Model,
			messages   = messages,
			tools      = toOpenAITools(),
			max_tokens = maxTokens,
		})

		local ok, res = pcall(httpRequest, {
			Url = provider.Endpoint,
			Method = "POST",
			Headers = {
				["Authorization"] = "Bearer " .. tostring(provider.ApiKey),
				["Content-Type"]  = "application/json",
			},
			Body = body,
		})
		if not ok then return nil, tostring(res), false end

		if res.StatusCode and res.StatusCode ~= 200 then
			local message = res.Body
			local parseOk, parsed = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if parseOk and type(parsed) == "table" then
				local errField = parsed.error
				if type(errField) == "table" and errField.message then
					message = tostring(errField.message)
				elseif type(errField) == "string" then
					message = errField
				end
			end
			local rateLimited = res.StatusCode == 429
			if rateLimited then message = message .. " (daily free-tier limit)" end
			return nil, provider.Name .. " API error " .. tostring(res.StatusCode) .. ": " .. message, rateLimited
		end

		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not decodeOk then return nil, provider.Name .. ": failed to decode API response.", false end
		return decoded, nil, false
	end

	local function callAI(messages)
		if not httpRequest then
			return nil, "Your executor doesn't support HTTP requests."
		end
		local lastErr = "No AI provider configured -- add at least one entry with an ApiKey to Providers."
		for _, provider in ipairs(providers) do
			if provider.ApiKey and provider.ApiKey ~= "" then
				local decoded, err, rateLimited = callProvider(provider, messages)
				if decoded then return decoded end
				lastErr = err
				if not rateLimited then return nil, lastErr end
			end
		end
		return nil, lastErr
	end

	local assistant = {}
	local stopRequested = false
	local busy = false

	function assistant:Stop()
		stopRequested = true
	end

	function assistant:IsBusy()
		return busy
	end

	function assistant:GetHistory()
		return conversation
	end

	function assistant:Reset()
		table.clear(conversation)
		table.insert(conversation, { role = "system", content = systemPrompt })
		saveHistory()
	end

	function assistant:Ask(panel, userText)
		table.insert(conversation, { role = "user", content = userText })
		panel:ShowTyping()
		stopRequested = false
		busy = true

		for _ = 1, maxRounds do
			if stopRequested then
				busy = false
				panel:HideTyping()
				panel:AddMessage("assistant", "(stopped)")
				saveHistory()
				return
			end

			local response, err = callAI(conversation)
			if not response then
				busy = false
				panel:HideTyping()
				panel:AddMessage("assistant", "Error: " .. tostring(err))
				saveHistory()
				return
			end

			local choice  = response.choices and response.choices[1]
			local message = choice and choice.message
			if not message then
				busy = false
				panel:HideTyping()
				panel:AddMessage("assistant", "Error: empty response from API.")
				saveHistory()
				return
			end

			table.insert(conversation, message)

			local calls = message.tool_calls
			local hasCalls = calls and #calls > 0
			local content = message.content or ""

			local _, fenceCount = content:gsub("```", "")
			local truncated = choice.finish_reason == "length" or fenceCount % 2 == 1

			if message.content and message.content ~= "" then
				if not hasCalls and not truncated then panel:HideTyping() end
				panel:AddMessage("assistant", message.content)
			end

			if hasCalls then
				for _, call in ipairs(calls) do
					local argsOk, args = pcall(function()
						return HttpService:JSONDecode(call["function"].arguments)
					end)
					local result = panel:HandleToolCall(call["function"].name, argsOk and args or {})
					table.insert(conversation, {
						role = "tool",
						tool_call_id = call.id,
						content = HttpService:JSONEncode(result == nil and {} or result),
					})
				end
			elseif truncated then
				table.insert(conversation, {
					role = "user",
					content = "You got cut off. Continue exactly where you left off -- don't repeat "
						.. "anything, don't restart the explanation.",
				})
			else
				busy = false
				panel:HideTyping()
				saveHistory()
				return
			end
		end

		busy = false
		panel:HideTyping()
		panel:AddMessage("assistant",
			"(stopped after several rounds of tool calls/continuations -- ask me to continue if you need to)")
		saveHistory()
	end

	return assistant
end


end,
}
