--!nonstrict
return {
Name = "chat-common", API = 1,
Requires = {},
Install = function(context)
	local AddContentScrollThumb = context.AddContentScrollThumb
	local AddScrollbar = context.AddScrollbar
	local Corner = context.Corner
	local NullUI = context.NullUI
	local ResolveIcon = context.ResolveIcon
	local Stroke = context.Stroke
	local Tween = context.Tween
local function CreateChatComposer(content, INPUT_H, BASE_Z, jan, placeholder)
	local inputRow = Instance.new("Frame")
	inputRow.BackgroundTransparency = 1
	inputRow.Active = true
	inputRow.AnchorPoint = Vector2.new(0, 1)
	inputRow.Position = UDim2.new(0, 0, 1, 0)
	inputRow.Size = UDim2.new(1, 0, 0, INPUT_H)
	inputRow.ZIndex = BASE_Z
	inputRow.Parent = content

	local pill = Instance.new("Frame")
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(INPUT_H + 6), 1, 0)
	pill.ZIndex = BASE_Z + 1
	pill.Parent = inputRow
	Corner(pill, 9)
	local pillStroke = Stroke(pill, Color3.new(1, 1, 1), 1, 0.9)

	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill

	local inputBox = Instance.new("TextBox")
	inputBox.BackgroundTransparency = 1
	inputBox.ClearTextOnFocus = false
	inputBox.FontFace = NullUI.Theme.FontRegular
	inputBox.PlaceholderText = placeholder
	inputBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
	inputBox.Text = ""
	inputBox.TextColor3 = NullUI.Theme.Text
	inputBox.TextSize = 13
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.TextYAlignment = Enum.TextYAlignment.Center
	inputBox.ClipsDescendants = true
	inputBox.Size = UDim2.fromScale(1, 1)
	inputBox.ZIndex = BASE_Z + 2
	inputBox.Parent = pill

	jan:Add(inputBox.Focused:Connect(function()
		Tween(pillStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
	end))
	jan:Add(inputBox.FocusLost:Connect(function()
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.9 }, 0.15)
	end))

	local sendBtn = Instance.new("TextButton")
	sendBtn.Name = "Send"
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(INPUT_H, INPUT_H)
	sendBtn.ZIndex = BASE_Z + 1
	sendBtn.Parent = inputRow
	Corner(sendBtn, 9)

	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon("send")
	sendIcon.ImageColor3 = NullUI.Theme.Text
	sendIcon.Size = UDim2.fromOffset(14, 14)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = BASE_Z + 2
	sendIcon.Parent = sendBtn

	jan:Add(sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end))
	jan:Add(sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end))


	return inputRow, pill, inputBox, sendBtn, sendIcon
end

local function CreateChatMessages(content, panel, HEADER_H, INPUT_H, BASE_Z, jan)
	local msgScroll = Instance.new("ScrollingFrame")
	msgScroll.BackgroundTransparency = 1
	msgScroll.BorderSizePixel = 0
	msgScroll.Position = UDim2.fromOffset(0, HEADER_H + 9)
	msgScroll.Size = UDim2.new(1, 0, 1, -(HEADER_H + 9 + INPUT_H + 10))
	msgScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	msgScroll.ScrollBarThickness = 0
	msgScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	msgScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	msgScroll.ZIndex = BASE_Z
	msgScroll.Parent = content

	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingRight = UDim.new(0, 18)
	msgPad.Parent = msgScroll

	local msgLayout = Instance.new("UIListLayout")
	msgLayout.Padding = UDim.new(0, 8)
	msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout.Parent = msgScroll

	AddScrollbar(msgScroll)
	AddContentScrollThumb(msgScroll, msgLayout, panel, jan)


	return msgScroll, msgLayout
end

local function BindChatAutoscroll(msgScroll, jan)
	local pinnedToBottom = true
	jan:Add(msgScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if pinnedToBottom then
			msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
		end
	end))
	jan:Add(msgScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = msgScroll.CanvasPosition.Y
			>= msgScroll.AbsoluteCanvasSize.Y - msgScroll.AbsoluteWindowSize.Y - 20
		pinnedToBottom = atBottom
	end))

	local function scrollToBottom()
		pinnedToBottom = true
		task.defer(function()
			if msgScroll and msgScroll.Parent then
				msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
			end
		end)
	end


	return scrollToBottom
end

local function ChatHeaderButton(controls, BASE_Z, jan, icon, layoutOrder)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(22, 22)
		btn.LayoutOrder = layoutOrder
		btn.ZIndex = BASE_Z + 1
		btn.Parent = controls
		Corner(btn, 6)

		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = NullUI.Theme.TextDim
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = BASE_Z + 2
		ic.Parent = btn

		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = NullUI.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = NullUI.Theme.TextDim }, 0.12)
		end))

		return btn, ic
	end

context.Shared = { CreateChatComposer = CreateChatComposer, CreateChatMessages = CreateChatMessages, BindChatAutoscroll = BindChatAutoscroll, ChatHeaderButton = ChatHeaderButton }

end,
}
