--!nonstrict
return {
Name = "spotify", API = 1,
Requires = {},
Install = function(context)
	local ASSETS_FOLDER = context.ASSETS_FOLDER
	local Corner = context.Corner
	local EnsureAssetsFolder = context.EnsureAssetsFolder
	local HttpService = context.HttpService
	local NullUI = context.NullUI
	local ResolveIcon = context.ResolveIcon
	local RunService = context.RunService
	local Stroke = context.Stroke
	local Tab = context.Tab
	local UserInputService = context.UserInputService
	local Window = context.Window
	local Z = context.Z
	local fn_customasset = context.fn_customasset
	local fn_isfile = context.fn_isfile
	local fn_readfile = context.fn_readfile
	local fn_writefile = context.fn_writefile
	local hasFn = context.hasFn
function Window:AddSpotifyPanel(opts)
	opts = opts or {}
	local jan = self._janitor
	local dockBtn
	local connectBridge
	local hasOpenedSpotify = false
	local panel
	panel = self:AddPanelTab({
		Name = opts.Name or "Spotify",
		Icon = opts.Icon or "Lucide:music-2",
		OnToggle = function(isOpen)
			if dockBtn then dockBtn:SetActive(isOpen) end
			if isOpen and not hasOpenedSpotify then
				hasOpenedSpotify = true
				if opts.AutoConnect == true and opts.BridgeUrl ~= "" then
					task.defer(function()
						if connectBridge then connectBridge() end
					end)
				end
			end
			if opts.OnToggle then task.spawn(opts.OnToggle, isOpen) end
		end,
	})

	local function websocketConnect()
		local candidates = {}
		pcall(function()
			if WebSocket and type(WebSocket.connect) == "function" then
				table.insert(candidates, WebSocket.connect)
			end
		end)
		pcall(function()
			if websocket and type(websocket.connect) == "function" then
				table.insert(candidates, websocket.connect)
			end
		end)
		pcall(function()
			if syn and syn.websocket and type(syn.websocket.connect) == "function" then
				table.insert(candidates, syn.websocket.connect)
			end
		end)
		return candidates[1]
	end

	local HEADER_H = 0
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = panel.Instance
	header.Visible = false

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header

	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "Lucide:music-2")
	titleIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
	titleIcon.AnchorPoint = Vector2.new(0, 0.5)
	titleIcon.Position = UDim2.new(0, 0, 0.5, 0)
	titleIcon.Size = UDim2.fromOffset(15, 15)
	titleIcon.ZIndex = Z.Content + 2
	titleIcon.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = opts.Title or "Spotify Player"
	titleLabel.TextColor3 = NullUI.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, 22, 0.5, 0)
	titleLabel.Size = UDim2.new(1, -62, 0, 18)
	titleLabel.ZIndex = Z.Content + 2
	titleLabel.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundTransparency = 1
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.ZIndex = Z.Content + 2
	closeBtn.Parent = header

	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	closeIcon.ImageColor3 = NullUI.Theme.TextDim
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.Size = UDim2.fromOffset(13, 13)
	closeIcon.ZIndex = Z.Content + 3
	closeIcon.Parent = closeBtn
	jan:Add(closeBtn.MouseButton1Click:Connect(function() panel.Close() end))

	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = panel.Instance
	divider.Visible = false

	local subTabHost = Instance.new("ScrollingFrame")
	subTabHost.Name = "SpotifySubTabs"
	subTabHost.BackgroundTransparency = 1
	subTabHost.BorderSizePixel = 0
	subTabHost.Position = UDim2.fromOffset(0, HEADER_H)
	subTabHost.Size = UDim2.new(1, 0, 1, -HEADER_H)
	subTabHost.ScrollBarThickness = 0
	subTabHost.ZIndex = Z.Content + 1
	subTabHost.Parent = panel.Instance

	local subTabRoot = setmetatable({
		Name = "Spotify Player",
		_page = subTabHost,
		_window = self,
		_janitor = jan,
		_group = panel.Instance,
	}, Tab)
	local playerSubTab = subTabRoot:AddSubTab({ Name = "Spotify Player", Icon = "Lucide:music-2" })
	local favoritesSubTab = subTabRoot:AddSubTab({ Name = "Favorites", Icon = "Lucide:heart" })
	local scroll = playerSubTab._page
	local list = scroll:FindFirstChild("PageLayout")
	local scrollPad = scroll:FindFirstChild("PagePadding")
	if scrollPad then
		scrollPad.PaddingTop = UDim.new(0, 0)
		scrollPad.PaddingLeft = UDim.new(0, 0)
		scrollPad.PaddingRight = UDim.new(0, 12)
		scrollPad.PaddingBottom = UDim.new(0, 6)
	end
	local favoritesPad = favoritesSubTab._page:FindFirstChild("PagePadding")
	if favoritesPad then
		favoritesPad.PaddingTop = UDim.new(0, 0)
		favoritesPad.PaddingLeft = UDim.new(0, 0)
		favoritesPad.PaddingRight = UDim.new(0, 12)
		favoritesPad.PaddingBottom = UDim.new(0, 6)
	end

	local function makeCard(height, order, parent)
		local card = Instance.new("Frame")
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.BackgroundTransparency = 0.96
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, height)
		card.LayoutOrder = order
		card.ZIndex = Z.Content + 2
		card.Parent = parent or scroll
		Corner(card, 10)
		Stroke(card, Color3.new(1, 1, 1), 1, 0.94)
		return card
	end

	local guideParagraph = playerSubTab:AddParagraph({
		Title = "Quick setup",
		Icon = "Lucide:link-2",
		Text = "Copy the player link, keep it open in your browser, load a playlist and press Play once.",
	})
	guideParagraph.Instance.LayoutOrder = 1

	local statusCard = makeCard(30, 6)
	local statusDot = Instance.new("Frame")
	statusDot.BackgroundColor3 = Color3.fromRGB(125, 130, 128)
	statusDot.BorderSizePixel = 0
	statusDot.AnchorPoint = Vector2.new(0, 0.5)
	statusDot.Position = UDim2.new(0, 11, 0.5, 0)
	statusDot.Size = UDim2.fromOffset(7, 7)
	statusDot.ZIndex = Z.Content + 3
	statusDot.Parent = statusCard
	Corner(statusDot, 4)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.FontFace = NullUI.Theme.FontRegular
	statusLabel.Text = "Bridge disconnected"
	statusLabel.TextColor3 = NullUI.Theme.TextDim
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Position = UDim2.fromOffset(27, 0)
	statusLabel.Size = UDim2.new(1, -38, 1, 0)
	statusLabel.ZIndex = Z.Content + 3
	statusLabel.Parent = statusCard

	local nowCard = makeCard(164, 7)
	nowCard.ClipsDescendants = true
	local art = Instance.new("ImageLabel")
	art.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
	art.BackgroundTransparency = 0.84
	art.BorderSizePixel = 0
	art.Image = ""
	art.ImageColor3 = Color3.new(1, 1, 1)
	art.ScaleType = Enum.ScaleType.Crop
	art.AnchorPoint = Vector2.new(0, 0)
	art.Position = UDim2.fromOffset(0, 12)
	art.Size = UDim2.fromOffset(88, 88)
	art.ZIndex = Z.Content + 3
	art.Parent = nowCard
	Corner(art, 12)
	Stroke(art, Color3.new(1, 1, 1), 1, 0.9)

	local artIcon = Instance.new("ImageLabel")
	artIcon.BackgroundTransparency = 1
	artIcon.Image = ResolveIcon("music-2")
	artIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
	artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	artIcon.Position = UDim2.fromScale(0.5, 0.5)
	artIcon.Size = UDim2.fromOffset(28, 28)
	artIcon.ZIndex = Z.Content + 4
	artIcon.Parent = art

	local coverToken = 0
	local coverCache = {}
	local function showCover(url)
		coverToken += 1
		local token = coverToken
		url = type(url) == "string" and url or ""
		if url == "" then
			art.BackgroundTransparency = 0.84
			art.Image = ""
			artIcon.Visible = true
			artIcon.Image = ResolveIcon("music-2")
			artIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
			artIcon.BackgroundTransparency = 1
			artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			artIcon.Size = UDim2.fromOffset(28, 28)
			artIcon.Position = UDim2.fromScale(0.5, 0.5)
			return
		end
		task.spawn(function()
			local asset = coverCache[url]
			if not asset and fn_customasset and fn_writefile and EnsureAssetsFolder() then
				local hash = 7
				for index = 1, #url do hash = (hash * 31 + url:byte(index)) % 2147483647 end
				local path = ASSETS_FOLDER .. "/spotify-cover-" .. tostring(hash) .. ".jpg"
				if not (fn_isfile and fn_isfile(path)) then
					local ok, body = pcall(function() return game:HttpGet(url) end)
					if ok and type(body) == "string" and #body > 256 then pcall(fn_writefile, path, body) end
				end
				if not fn_isfile or fn_isfile(path) then
					local ok, result = pcall(fn_customasset, path)
					if ok then asset = result; coverCache[url] = result end
				end
			end
			if token ~= coverToken or not asset then return end
			art.BackgroundTransparency = 1
			art.Image = asset
			artIcon.Visible = false
		end)
	end

	local nowPlayingTag = Instance.new("TextLabel")
	nowPlayingTag.BackgroundTransparency = 1
	nowPlayingTag.FontFace = NullUI.Theme.Font
	nowPlayingTag.Text = "NOW PLAYING"
	nowPlayingTag.TextColor3 = Color3.fromRGB(30, 215, 96)
	nowPlayingTag.TextSize = 9
	nowPlayingTag.TextXAlignment = Enum.TextXAlignment.Left
	nowPlayingTag.Position = UDim2.fromOffset(100, 9)
	nowPlayingTag.Size = UDim2.new(1, -100, 0, 12)
	nowPlayingTag.ZIndex = Z.Content + 3
	nowPlayingTag.Parent = nowCard

	local trackLabel = Instance.new("TextLabel")
	trackLabel.BackgroundTransparency = 1
	trackLabel.FontFace = NullUI.Theme.Font
	trackLabel.Text = "Nothing playing"
	trackLabel.TextColor3 = NullUI.Theme.Text
	trackLabel.TextSize = 15
	trackLabel.TextXAlignment = Enum.TextXAlignment.Left
	trackLabel.TextTruncate = Enum.TextTruncate.AtEnd
	trackLabel.Position = UDim2.fromOffset(100, 25)
	trackLabel.Size = UDim2.new(1, -100, 0, 20)
	trackLabel.ZIndex = Z.Content + 3
	trackLabel.Parent = nowCard

	local artistLabel = Instance.new("TextLabel")
	artistLabel.BackgroundTransparency = 1
	artistLabel.FontFace = NullUI.Theme.FontRegular
	artistLabel.Text = "Connect your Spotify bridge"
	artistLabel.TextColor3 = NullUI.Theme.TextDim
	artistLabel.TextSize = 12
	artistLabel.TextXAlignment = Enum.TextXAlignment.Left
	artistLabel.TextTruncate = Enum.TextTruncate.AtEnd
	artistLabel.Position = UDim2.fromOffset(100, 47)
	artistLabel.Size = UDim2.new(1, -100, 0, 16)
	artistLabel.ZIndex = Z.Content + 3
	artistLabel.Parent = nowCard

	local progressTrack = Instance.new("Frame")
	progressTrack.BackgroundColor3 = Color3.fromRGB(95, 100, 98)
	progressTrack.BackgroundTransparency = 0.45
	progressTrack.BorderSizePixel = 0
	progressTrack.Position = UDim2.fromOffset(100, 76)
	progressTrack.Size = UDim2.new(1, -100, 0, 5)
	progressTrack.ZIndex = Z.Content + 3
	progressTrack.Parent = nowCard
	Corner(progressTrack, 2)

	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.ZIndex = Z.Content + 4
	progressFill.Parent = progressTrack
	Corner(progressFill, 2)

	local progressKnob = Instance.new("Frame")
	progressKnob.BackgroundColor3 = Color3.fromRGB(235, 239, 237)
	progressKnob.BorderSizePixel = 0
	progressKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	progressKnob.Position = UDim2.new(0, 0, 0.5, 0)
	progressKnob.Size = UDim2.fromOffset(9, 9)
	progressKnob.ZIndex = Z.Content + 6
	progressKnob.Parent = progressTrack
	Corner(progressKnob, 5)

	local seekBubble = Instance.new("Frame")
	seekBubble.BackgroundColor3 = Color3.fromRGB(21, 26, 24)
	seekBubble.BackgroundTransparency = 0.04
	seekBubble.BorderSizePixel = 0
	seekBubble.AnchorPoint = Vector2.new(0.5, 1)
	seekBubble.Position = UDim2.new(0, 0, 0, -8)
	seekBubble.Size = UDim2.fromOffset(48, 25)
	seekBubble.Visible = false
	seekBubble.ZIndex = Z.Content + 8
	seekBubble.Parent = progressTrack
	Corner(seekBubble, 7)
	Stroke(seekBubble, Color3.new(1, 1, 1), 1, 0.9)
	local seekBubbleLabel = Instance.new("TextLabel")
	seekBubbleLabel.BackgroundTransparency = 1
	seekBubbleLabel.FontFace = NullUI.Theme.Font
	seekBubbleLabel.Text = "0:00"
	seekBubbleLabel.TextColor3 = NullUI.Theme.Text
	seekBubbleLabel.TextSize = 10
	seekBubbleLabel.Size = UDim2.fromScale(1, 1)
	seekBubbleLabel.ZIndex = Z.Content + 9
	seekBubbleLabel.Parent = seekBubble

	local progressHitbox = Instance.new("TextButton")
	progressHitbox.Text = ""
	progressHitbox.AutoButtonColor = false
	progressHitbox.BackgroundTransparency = 1
	progressHitbox.BorderSizePixel = 0
	progressHitbox.Position = UDim2.fromOffset(100, 68)
	progressHitbox.Size = UDim2.new(1, -100, 0, 21)
	progressHitbox.ZIndex = Z.Content + 7
	progressHitbox.Parent = nowCard

	local timeLabel = Instance.new("TextLabel")
	timeLabel.BackgroundTransparency = 1
	timeLabel.FontFace = NullUI.Theme.FontRegular
	timeLabel.Text = "0:00"
	timeLabel.TextColor3 = NullUI.Theme.TextDim
	timeLabel.TextSize = 10
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Position = UDim2.fromOffset(100, 87)
	timeLabel.Size = UDim2.new(0.5, -50, 0, 14)
	timeLabel.ZIndex = Z.Content + 3
	timeLabel.Parent = nowCard

	local durationLabel = Instance.new("TextLabel")
	durationLabel.BackgroundTransparency = 1
	durationLabel.FontFace = NullUI.Theme.FontRegular
	durationLabel.Text = "0:00"
	durationLabel.TextColor3 = NullUI.Theme.TextDim
	durationLabel.TextSize = 10
	durationLabel.TextXAlignment = Enum.TextXAlignment.Right
	durationLabel.Position = UDim2.new(0.5, 50, 0, 87)
	durationLabel.Size = UDim2.new(0.5, -50, 0, 14)
	durationLabel.ZIndex = Z.Content + 3
	durationLabel.Parent = nowCard

	local controlsDivider = Instance.new("Frame")
	controlsDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	controlsDivider.BackgroundTransparency = 0.93
	controlsDivider.BorderSizePixel = 0
	controlsDivider.Position = UDim2.fromOffset(0, 111)
	controlsDivider.Size = UDim2.new(1, 0, 0, 1)
	controlsDivider.ZIndex = Z.Content + 3
	controlsDivider.Parent = nowCard

	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.BorderSizePixel = 0
	controls.Position = UDim2.fromOffset(0, 114)
	controls.Size = UDim2.new(1, 0, 0, 44)
	controls.ZIndex = Z.Content + 3
	controls.Parent = nowCard
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 12)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controls

	local controlRefs = {}
	local function makeControl(name, icon, order, primary)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = primary and Color3.fromRGB(30, 215, 96) or Color3.new(1, 1, 1)
		button.BackgroundTransparency = primary and 0.05 or 0.94
		button.BorderSizePixel = 0
		button.Size = UDim2.fromOffset(primary and 36 or 32, primary and 36 or 32)
		button.LayoutOrder = order
		button.ZIndex = Z.Content + 3
		button.Parent = controls
		Corner(button, primary and 18 or 10)

		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = ResolveIcon(icon)
		image.ImageColor3 = primary and Color3.fromRGB(12, 28, 18) or NullUI.Theme.TextDim
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(primary and 17 or 15, primary and 17 or 15)
		image.ZIndex = Z.Content + 4
		image.Parent = button
		controlRefs[name] = { Button = button, Icon = image }
		return button
	end

	local shuffleBtn = makeControl("Shuffle", "shuffle", 1, false)
	local previousBtn = makeControl("Previous", "skip-back", 2, false)
	local playBtn = makeControl("PlayPause", "play", 3, true)
	local nextBtn = makeControl("Next", "skip-forward", 4, false)
	local repeatBtn = makeControl("Repeat", "repeat", 5, false)

	local function makeInputCard(order, title, placeholder, buttonIcon)
		local card = makeCard(66, order)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = NullUI.Theme.Font
		label.Text = title
		label.TextColor3 = NullUI.Theme.Text
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(11, 6)
		label.Size = UDim2.new(1, -22, 0, 16)
		label.ZIndex = Z.Content + 3
		label.Parent = card

		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.BackgroundTransparency = 0.94
		pill.BorderSizePixel = 0
		pill.Position = UDim2.fromOffset(10, 27)
		pill.Size = UDim2.new(1, -20, 0, 30)
		pill.ZIndex = Z.Content + 3
		pill.Parent = card
		Corner(pill, 8)

		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = 0.91
		button.BorderSizePixel = 0
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -3, 0, 3)
		button.Size = UDim2.fromOffset(34, 24)
		button.ZIndex = Z.Content + 5
		button.Parent = pill
		Corner(button, 7)
		Stroke(button, Color3.new(1, 1, 1), 1, 0.94)
		local buttonImage = Instance.new("ImageLabel")
		buttonImage.BackgroundTransparency = 1
		buttonImage.Image = ResolveIcon(buttonIcon)
		buttonImage.ImageColor3 = NullUI.Theme.Text
		buttonImage.AnchorPoint = Vector2.new(0.5, 0.5)
		buttonImage.Position = UDim2.fromScale(0.5, 0.5)
		buttonImage.Size = UDim2.fromOffset(14, 14)
		buttonImage.ZIndex = Z.Content + 6
		buttonImage.Parent = button

		local box = Instance.new("TextBox")
		box.ClearTextOnFocus = false
		box.FontFace = NullUI.Theme.FontRegular
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = Color3.fromRGB(115, 120, 118)
		box.Text = ""
		box.TextColor3 = NullUI.Theme.Text
		box.TextSize = 11
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.BackgroundTransparency = 1
		box.Position = UDim2.fromOffset(9, 0)
		box.Size = UDim2.new(1, -52, 1, 0)
		box.ZIndex = Z.Content + 4
		box.Parent = pill
		return box, button, card, label, pill
	end

	local searchBox, searchBtn, searchCard, searchTitle, searchPill = makeInputCard(3, "", "Search this playlist...", "search")
	local pairBox, connectBtn, pairCard = makeInputCard(3, "Spotify Connect", "Pairing code", "link-2")
	local connectBtnIcon = connectBtn:FindFirstChildOfClass("ImageLabel")
	pairBox.TextEditable = false
	pairBox.Text = HttpService:GenerateGUID(false):gsub("%-", ""):sub(1, 8):upper()
	local playlistBox, loadBtn, playlistCard, playlistTitle, playlistPill = makeInputCard(4, "", "Paste a Spotify playlist link...", "play")

	local connectSection = playerSubTab:AddLineText("Spotify Connect")
	connectSection.Instance.LayoutOrder = 2
	local playerSection = playerSubTab:AddLineText("Player")
	playerSection.Instance.LayoutOrder = 4
	local playerShell = makeCard(286, 5)
	local function flattenIntoPlayer(card, y, height)
		card.Parent = playerShell
		card.BackgroundTransparency = 1
		card.Position = UDim2.fromOffset(12, y)
		card.Size = UDim2.new(1, -24, 0, height)
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("UIStroke") then child.Transparency = 1 end
		end
	end
	flattenIntoPlayer(searchCard, 12, 40)
	searchTitle.Visible = false
	searchPill.Position = UDim2.fromOffset(0, 0)
	searchPill.Size = UDim2.fromScale(1, 1)
	searchPill.BackgroundTransparency = 0.92
	searchBtn.AnchorPoint = Vector2.zero
	searchBtn.Position = UDim2.fromOffset(4, 4)
	searchBtn.Size = UDim2.fromOffset(32, 32)
	searchBtn.BackgroundTransparency = 1
	for _, child in ipairs(searchBtn:GetChildren()) do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end
	searchBox.Position = UDim2.fromOffset(38, 0)
	searchBox.Size = UDim2.new(1, -46, 1, 0)
	searchBox.TextSize = 13

	flattenIntoPlayer(playlistCard, 60, 40)
	playlistTitle.Visible = false
	playlistPill.Position = UDim2.fromOffset(0, 0)
	playlistPill.Size = UDim2.fromScale(1, 1)
	playlistPill.BackgroundTransparency = 0.92
	loadBtn.Position = UDim2.new(1, -4, 0, 4)
	loadBtn.Size = UDim2.fromOffset(32, 32)
	playlistBox.Position = UDim2.fromOffset(12, 0)
	playlistBox.Size = UDim2.new(1, -56, 1, 0)

	statusCard.Parent = playerShell
	statusCard.Position = UDim2.fromOffset(12, 108)
	statusCard.Size = UDim2.new(1, -24, 0, 30)
	statusCard.Visible = false
	nowCard.Parent = playerShell
	nowCard.Position = UDim2.fromOffset(12, 108)
	nowCard.Size = UDim2.new(1, -24, 0, 164)
	nowCard.BackgroundTransparency = 1
	for _, child in ipairs(nowCard:GetChildren()) do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end

	local favoritesSection = favoritesSubTab:AddLineText("Saved Playlists")
	favoritesSection.Instance.LayoutOrder = 1
	local favoritesHeader = makeCard(137, 2, favoritesSubTab._page)
	local favoritesTitle = Instance.new("TextLabel")
	favoritesTitle.BackgroundTransparency = 1
	favoritesTitle.FontFace = NullUI.Theme.Font
	favoritesTitle.Text = "Favorite playlists"
	favoritesTitle.TextColor3 = NullUI.Theme.Text
	favoritesTitle.TextSize = 14
	favoritesTitle.TextXAlignment = Enum.TextXAlignment.Left
	favoritesTitle.Position = UDim2.fromOffset(12, 8)
	favoritesTitle.Size = UDim2.new(1, -112, 0, 20)
	favoritesTitle.ZIndex = Z.Content + 3
	favoritesTitle.Parent = favoritesHeader
	favoritesTitle.Visible = false
	local favoritesHint = Instance.new("TextLabel")
	favoritesHint.BackgroundTransparency = 1
	favoritesHint.FontFace = NullUI.Theme.FontRegular
	favoritesHint.Text = "Save and load your playlists with one tap"
	favoritesHint.TextColor3 = NullUI.Theme.TextDim
	favoritesHint.TextSize = 10
	favoritesHint.TextXAlignment = Enum.TextXAlignment.Left
	favoritesHint.Position = UDim2.fromOffset(12, 29)
	favoritesHint.Size = UDim2.new(1, -112, 0, 16)
	favoritesHint.ZIndex = Z.Content + 3
	favoritesHint.Parent = favoritesHeader
	favoritesHint.Visible = false
	local favoritesSearchPill = Instance.new("Frame")
	favoritesSearchPill.BackgroundColor3 = Color3.new(1, 1, 1)
	favoritesSearchPill.BackgroundTransparency = 0.94
	favoritesSearchPill.BorderSizePixel = 0
	favoritesSearchPill.Position = UDim2.fromOffset(8, 7)
	favoritesSearchPill.Size = UDim2.new(1, -16, 0, 36)
	favoritesSearchPill.ZIndex = Z.Content + 3
	favoritesSearchPill.Parent = favoritesHeader
	Corner(favoritesSearchPill, 9)
	local favoritesSearchIcon = Instance.new("ImageLabel")
	favoritesSearchIcon.BackgroundTransparency = 1
	favoritesSearchIcon.Image = ResolveIcon("search")
	favoritesSearchIcon.ImageColor3 = NullUI.Theme.TextDim
	favoritesSearchIcon.AnchorPoint = Vector2.new(0, 0.5)
	favoritesSearchIcon.Position = UDim2.new(0, 11, 0.5, 0)
	favoritesSearchIcon.Size = UDim2.fromOffset(15, 15)
	favoritesSearchIcon.ZIndex = Z.Content + 4
	favoritesSearchIcon.Parent = favoritesSearchPill
	local favoritesSearchBox = Instance.new("TextBox")
	favoritesSearchBox.BackgroundTransparency = 1
	favoritesSearchBox.ClearTextOnFocus = false
	favoritesSearchBox.FontFace = NullUI.Theme.FontRegular
	favoritesSearchBox.PlaceholderText = "Search favorite playlists..."
	favoritesSearchBox.PlaceholderColor3 = Color3.fromRGB(115, 120, 118)
	favoritesSearchBox.Text = ""
	favoritesSearchBox.TextColor3 = NullUI.Theme.Text
	favoritesSearchBox.TextSize = 11
	favoritesSearchBox.TextXAlignment = Enum.TextXAlignment.Left
	favoritesSearchBox.Position = UDim2.fromOffset(36, 0)
	favoritesSearchBox.Size = UDim2.new(1, -44, 1, 0)
	favoritesSearchBox.ZIndex = Z.Content + 4
	favoritesSearchBox.Parent = favoritesSearchPill
	local addFavoriteBtn = Instance.new("TextButton")
	addFavoriteBtn.Text = ""
	addFavoriteBtn.AutoButtonColor = false
	addFavoriteBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	addFavoriteBtn.BackgroundTransparency = 0.96
	addFavoriteBtn.BorderSizePixel = 0
	addFavoriteBtn.Position = UDim2.fromOffset(8, 113)
	addFavoriteBtn.Size = UDim2.new(1, -16, 0, 56)
	addFavoriteBtn.ZIndex = Z.Content + 4
	addFavoriteBtn.Parent = favoritesHeader
	Corner(addFavoriteBtn, 10)
	Stroke(addFavoriteBtn, Color3.new(1, 1, 1), 1, 0.94)
	local addFavoriteIcon = Instance.new("ImageLabel")
	addFavoriteIcon.BackgroundTransparency = 1
	addFavoriteIcon.Image = ResolveIcon("heart-plus")
	addFavoriteIcon.ImageColor3 = NullUI.Theme.Text
	addFavoriteIcon.AnchorPoint = Vector2.new(0, 0.5)
	addFavoriteIcon.Position = UDim2.new(0, 16, 0.5, 0)
	addFavoriteIcon.Size = UDim2.fromOffset(17, 17)
	addFavoriteIcon.ZIndex = Z.Content + 5
	addFavoriteIcon.Parent = addFavoriteBtn
	local saveFavoriteTitle = Instance.new("TextLabel")
	saveFavoriteTitle.BackgroundTransparency = 1
	saveFavoriteTitle.FontFace = NullUI.Theme.Font
	saveFavoriteTitle.Text = "Save current playlist"
	saveFavoriteTitle.TextColor3 = NullUI.Theme.Text
	saveFavoriteTitle.TextSize = 12
	saveFavoriteTitle.TextXAlignment = Enum.TextXAlignment.Left
	saveFavoriteTitle.Position = UDim2.fromOffset(44, 7)
	saveFavoriteTitle.Size = UDim2.new(1, -84, 0, 20)
	saveFavoriteTitle.ZIndex = Z.Content + 5
	saveFavoriteTitle.Parent = addFavoriteBtn
	local saveFavoriteHint = Instance.new("TextLabel")
	saveFavoriteHint.BackgroundTransparency = 1
	saveFavoriteHint.FontFace = NullUI.Theme.FontRegular
	saveFavoriteHint.Text = "Add the playlist loaded in the player to Favorites"
	saveFavoriteHint.TextColor3 = NullUI.Theme.TextDim
	saveFavoriteHint.TextSize = 9
	saveFavoriteHint.TextXAlignment = Enum.TextXAlignment.Left
	saveFavoriteHint.Position = UDim2.fromOffset(44, 27)
	saveFavoriteHint.Size = UDim2.new(1, -84, 0, 17)
	saveFavoriteHint.ZIndex = Z.Content + 5
	saveFavoriteHint.Parent = addFavoriteBtn
	local saveFavoriteChevron = Instance.new("ImageLabel")
	saveFavoriteChevron.BackgroundTransparency = 1
	saveFavoriteChevron.Image = ResolveIcon("chevron-right")
	saveFavoriteChevron.ImageColor3 = NullUI.Theme.TextDim
	saveFavoriteChevron.AnchorPoint = Vector2.new(1, 0.5)
	saveFavoriteChevron.Position = UDim2.new(1, -16, 0.5, 0)
	saveFavoriteChevron.Size = UDim2.fromOffset(14, 14)
	saveFavoriteChevron.ZIndex = Z.Content + 5
	saveFavoriteChevron.Parent = addFavoriteBtn
	local saveFavoriteDivider = Instance.new("Frame")
	saveFavoriteDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	saveFavoriteDivider.BackgroundTransparency = 0.92
	saveFavoriteDivider.BorderSizePixel = 0
	saveFavoriteDivider.Position = UDim2.fromOffset(8, 103)
	saveFavoriteDivider.Size = UDim2.new(1, -16, 0, 1)
	saveFavoriteDivider.ZIndex = Z.Content + 3
	saveFavoriteDivider.Parent = favoritesHeader

	local favoritesList = Instance.new("Frame")
	favoritesList.BackgroundTransparency = 1
	favoritesList.BorderSizePixel = 0
	favoritesList.Position = UDim2.fromOffset(8, 51)
	favoritesList.Size = UDim2.new(1, -16, 0, 78)
	favoritesList.ZIndex = Z.Content + 2
	favoritesList.Parent = favoritesHeader
	local favoriteRows = {}
	local favorites = {}
	local currentPlaylistName = "Spotify playlist"
	local favoritesPath = ASSETS_FOLDER .. "/spotify-favorites.json"
	if fn_readfile and fn_isfile and fn_isfile(favoritesPath) then
		pcall(function()
			local decoded = HttpService:JSONDecode(fn_readfile(favoritesPath))
			if type(decoded) == "table" then favorites = decoded end
		end)
	end
	local function saveFavorites()
		if not (fn_writefile and EnsureAssetsFolder()) then return end
		pcall(fn_writefile, favoritesPath, HttpService:JSONEncode(favorites))
	end

	local socket
	local socketConnections = {}
	local isConnected = false
	local isPlaying = false
	local shuffle = false
	local repeatMode = "off"
	local durationMs = 0
	local progressMs = 0
	local lastStateClock = os.clock()
	local seekDragging = false
	local seekPreviewMs = 0

	local function setStatus(text, color)
		statusLabel.Text = tostring(text or "")
		statusDot.BackgroundColor3 = color or Color3.fromRGB(125, 130, 128)
	end

	local notifyTimes = {}
	local function spotifyNotify(key, title, text, notifyType, icon, duration, actions)
		if not panel.IsOpen() then return end
		local now = os.clock()
		if notifyTimes[key] and now - notifyTimes[key] < 2.5 then return end
		notifyTimes[key] = now
		NullUI:Notify({
			Title = title,
			Text = text,
			Type = notifyType or "info",
			Icon = icon,
			Duration = duration or 5,
			Actions = actions,
		})
	end

	local function formatTime(ms)
		local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end

	local function renderProgress()
		local shownProgress = progressMs
		if isPlaying and durationMs > 0 then
			shownProgress = math.min(durationMs, progressMs + (os.clock() - lastStateClock) * 1000)
		end
		local alpha = durationMs > 0 and math.clamp(shownProgress / durationMs, 0, 1) or 0
		if not seekDragging then
			progressFill.Size = UDim2.new(alpha, 0, 1, 0)
			progressKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
			timeLabel.Text = formatTime(shownProgress)
		end
		durationLabel.Text = formatTime(durationMs)
	end
	jan:Add(RunService.Heartbeat:Connect(renderProgress))

	local function send(action, extra)
		if not (isConnected and socket) then
			setStatus("Connect the bridge first", Color3.fromRGB(255, 190, 90))
			return false
		end
		local payload = extra or {}
		payload.type = "command"
		payload.action = action
		local ok, err = pcall(function()
			socket:Send(HttpService:JSONEncode(payload))
		end)
		if not ok then
			setStatus("Could not send command: " .. tostring(err), Color3.fromRGB(255, 105, 105))
		end
		return ok
	end

	local function setView(name)
		subTabRoot:SelectSubTabByName(name)
	end

	local function renderFavorites()
		for _, row in ipairs(favoriteRows) do row:Destroy() end
		table.clear(favoriteRows)
		local query = favoritesSearchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		local filtered = {}
		for originalIndex, favorite in ipairs(favorites) do
			local searchable = (tostring(favorite.name or "") .. " " .. tostring(favorite.url or "")):lower()
			if query == "" or searchable:find(query, 1, true) then
				table.insert(filtered, { Favorite = favorite, Index = originalIndex })
			end
		end
		local count = math.min(#filtered, 8)
		local listHeight = count == 0 and 52 or count * 64
		favoritesList.Size = UDim2.new(1, -16, 0, listHeight)
		local dividerY = 51 + listHeight + 7
		saveFavoriteDivider.Position = UDim2.fromOffset(8, dividerY)
		addFavoriteBtn.Position = UDim2.fromOffset(8, dividerY + 10)
		favoritesHeader.Size = UDim2.new(1, 0, 0, dividerY + 74)
		if count == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.FontFace = NullUI.Theme.FontRegular
			empty.Text = query ~= "" and "No saved playlist matches your search" or "No saved playlists yet"
			empty.TextColor3 = NullUI.Theme.TextDim
			empty.TextSize = 11
			empty.Size = UDim2.fromScale(1, 1)
			empty.ZIndex = Z.Content + 3
			empty.Parent = favoritesList
			table.insert(favoriteRows, empty)
		else
		for visibleIndex = 1, count do
			local entry = filtered[visibleIndex]
			local favorite = entry.Favorite
			local originalIndex = entry.Index
			local row = Instance.new("Frame")
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = 0.96
			row.BorderSizePixel = 0
			row.Position = UDim2.fromOffset(0, (visibleIndex - 1) * 64)
			row.Size = UDim2.new(1, 0, 0, 58)
			row.ZIndex = Z.Content + 3
			row.Parent = favoritesList
			Corner(row, 10)
			Stroke(row, Color3.new(1, 1, 1), 1, 0.94)
			local playlistIconBox = Instance.new("Frame")
			playlistIconBox.BackgroundColor3 = Color3.new(1, 1, 1)
			playlistIconBox.BackgroundTransparency = 0.91
			playlistIconBox.BorderSizePixel = 0
			playlistIconBox.Position = UDim2.fromOffset(10, 9)
			playlistIconBox.Size = UDim2.fromOffset(40, 40)
			playlistIconBox.ZIndex = Z.Content + 4
			playlistIconBox.Parent = row
			Corner(playlistIconBox, 8)
			local playlistIcon = Instance.new("ImageLabel")
			playlistIcon.BackgroundTransparency = 1
			playlistIcon.Image = ResolveIcon("list-music")
			playlistIcon.ImageColor3 = NullUI.Theme.Text
			playlistIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			playlistIcon.Position = UDim2.fromScale(0.5, 0.5)
			playlistIcon.Size = UDim2.fromOffset(15, 15)
			playlistIcon.ZIndex = Z.Content + 5
			playlistIcon.Parent = playlistIconBox
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.FontFace = NullUI.Theme.Font
			name.Text = tostring(favorite.name or "Spotify playlist")
			name.TextColor3 = NullUI.Theme.Text
			name.TextSize = 11
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Position = UDim2.fromOffset(60, 8)
			name.Size = UDim2.new(1, -152, 0, 20)
			name.ZIndex = Z.Content + 4
			name.Parent = row
			local subtitle = Instance.new("TextLabel")
			subtitle.BackgroundTransparency = 1
			subtitle.FontFace = NullUI.Theme.FontRegular
			subtitle.Text = "Spotify playlist"
			subtitle.TextColor3 = NullUI.Theme.TextDim
			subtitle.TextSize = 9
			subtitle.TextXAlignment = Enum.TextXAlignment.Left
			subtitle.Position = UDim2.fromOffset(60, 30)
			subtitle.Size = UDim2.new(1, -152, 0, 16)
			subtitle.ZIndex = Z.Content + 4
			subtitle.Parent = row
			local loadFavorite = Instance.new("TextButton")
			loadFavorite.Text = ""
			loadFavorite.AutoButtonColor = false
			loadFavorite.BackgroundColor3 = Color3.new(1, 1, 1)
			loadFavorite.BackgroundTransparency = 0.91
			loadFavorite.BorderSizePixel = 0
			loadFavorite.Position = UDim2.new(1, -76, 0, 13)
			loadFavorite.Size = UDim2.fromOffset(32, 32)
			loadFavorite.ZIndex = Z.Content + 5
			loadFavorite.Parent = row
			Corner(loadFavorite, 8)
			local loadFavoriteIcon = Instance.new("ImageLabel")
			loadFavoriteIcon.BackgroundTransparency = 1
			loadFavoriteIcon.Image = ResolveIcon("play")
			loadFavoriteIcon.ImageColor3 = NullUI.Theme.Text
			loadFavoriteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			loadFavoriteIcon.Position = UDim2.fromScale(0.5, 0.5)
			loadFavoriteIcon.Size = UDim2.fromOffset(13, 13)
			loadFavoriteIcon.ZIndex = Z.Content + 6
			loadFavoriteIcon.Parent = loadFavorite
			local removeFavorite = Instance.new("TextButton")
			removeFavorite.Text = ""
			removeFavorite.BackgroundColor3 = Color3.new(1, 1, 1)
			removeFavorite.BackgroundTransparency = 0.94
			removeFavorite.Position = UDim2.new(1, -38, 0, 13)
			removeFavorite.Size = UDim2.fromOffset(30, 32)
			removeFavorite.ZIndex = Z.Content + 5
			removeFavorite.Parent = row
			Corner(removeFavorite, 8)
			local removeFavoriteIcon = Instance.new("ImageLabel")
			removeFavoriteIcon.BackgroundTransparency = 1
			removeFavoriteIcon.Image = ResolveIcon("trash-2")
			removeFavoriteIcon.ImageColor3 = Color3.fromRGB(220, 125, 125)
			removeFavoriteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			removeFavoriteIcon.Position = UDim2.fromScale(0.5, 0.5)
			removeFavoriteIcon.Size = UDim2.fromOffset(13, 13)
			removeFavoriteIcon.ZIndex = Z.Content + 6
			removeFavoriteIcon.Parent = removeFavorite
			jan:Add(loadFavorite.MouseButton1Click:Connect(function()
				playlistBox.Text = tostring(favorite.url or "")
				setView("Spotify Player")
				if send("load_playlist", { url = playlistBox.Text }) then
					setStatus("Loading favorite playlist...", Color3.fromRGB(30, 215, 96))
					spotifyNotify("favorite_load", "Open Spotify Bridge", "Open the browser site, wait for the playlist and press Play once. Then return to Roblox to control it here.", "warning", "external-link", 8)
				end
			end))
			jan:Add(removeFavorite.MouseButton1Click:Connect(function()
				local removedName = tostring(favorite.name or "Spotify playlist")
				table.remove(favorites, originalIndex)
				saveFavorites()
				renderFavorites()
				spotifyNotify("favorite_removed", "Favorite removed", removedName, "success", "trash-2", 3)
			end))
			table.insert(favoriteRows, row)
		end
		end
	end
	jan:Add(favoritesSearchBox:GetPropertyChangedSignal("Text"):Connect(renderFavorites))

	jan:Add(addFavoriteBtn.MouseButton1Click:Connect(function()
		local url = playlistBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if url == "" then
			spotifyNotify("favorite_missing", "Nothing to save", "Paste or load a Spotify playlist first.", "warning", "heart", 4)
			return
		end
		for _, favorite in ipairs(favorites) do
			if favorite.url == url then
				spotifyNotify("favorite_duplicate", "Already saved", "This playlist is already in your favorites.", "warning", "heart", 4)
				return
			end
		end
		table.insert(favorites, 1, { name = currentPlaylistName, url = url })
		saveFavorites()
		renderFavorites()
		spotifyNotify("favorite_saved", "Playlist saved", currentPlaylistName .. " was added to Favorites.", "success", "heart", 4)
	end))
	renderFavorites()

	local function paintModes()
		controlRefs.PlayPause.Icon.Image = ResolveIcon(isPlaying and "pause" or "play")
		controlRefs.Shuffle.Icon.ImageColor3 = shuffle and Color3.fromRGB(30, 215, 96) or NullUI.Theme.TextDim
		controlRefs.Repeat.Icon.ImageColor3 = repeatMode ~= "off" and Color3.fromRGB(30, 215, 96) or NullUI.Theme.TextDim
	end

	local function applyState(data)
		local track = data.track or data.item or {}
		local artists = track.artist or track.artists or data.artist
		if type(artists) == "table" then
			local names = {}
			for _, artist in ipairs(artists) do
				table.insert(names, type(artist) == "table" and tostring(artist.name or "") or tostring(artist))
			end
			artists = table.concat(names, ", ")
		end
		trackLabel.Text = tostring(track.name or data.trackName or "Nothing playing")
		artistLabel.Text = tostring(artists or "Spotify")
		showCover(track.image or track.imageUrl or track.albumArt or data.image or data.imageUrl)
		isPlaying = data.isPlaying == true or data.playing == true
		shuffle = data.shuffle == true or data.shuffleState == true
		repeatMode = tostring(data.repeatMode or data.repeat_state or "off")
		durationMs = tonumber(track.durationMs or track.duration_ms or data.durationMs or data.duration_ms) or 0
		progressMs = tonumber(data.progressMs or data.progress_ms or data.positionMs or data.position_ms) or 0
		lastStateClock = os.clock()
		paintModes()
		renderProgress()
		if trackLabel.Text ~= "Playlist ready" and trackLabel.Text ~= "Nothing playing" then
			setStatus(isPlaying and "Playing — controls synced" or "Paused — controls synced", Color3.fromRGB(30, 215, 96))
		end
	end

	local function clearSocketConnections()
		for _, connection in ipairs(socketConnections) do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(socketConnections)
	end

	local function disconnectBridge(silent)
		clearSocketConnections()
		local oldSocket = socket
		socket = nil
		isConnected = false
		if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("link-2") end
		if oldSocket then pcall(function() oldSocket:Close() end) end
		if not silent then setStatus("Bridge disconnected", Color3.fromRGB(125, 130, 128)) end
	end

	local function bindSocketEvent(event, callback)
		if event and type(event.Connect) == "function" then
			local ok, connection = pcall(function() return event:Connect(callback) end)
			if ok and connection then table.insert(socketConnections, connection) end
		end
	end

	connectBridge = function()
		if isConnected then
			local pageUrl = tostring(opts.ConnectUrl or "")
			local pairUrl = pageUrl .. (pageUrl:find("?", 1, true) and "&" or "?") .. "code=" .. pairBox.Text
			local copy = hasFn("setclipboard")
			if copy then
				pcall(copy, pairUrl)
				setStatus("Player link copied — open it in your browser", Color3.fromRGB(30, 215, 96))
				spotifyNotify("link_copied", "Player link copied", "Open the link in your browser and keep that tab running.", "success", "external-link", 6, {
					{ Text = "Copy again", Callback = function() pcall(copy, pairUrl) end },
				})
			else
				setStatus("Open the player page and enter code " .. pairBox.Text, Color3.fromRGB(255, 190, 90))
				spotifyNotify("manual_code", "Open Spotify Bridge", "Clipboard is unavailable. Open the player page and enter code " .. pairBox.Text .. ".", "warning", "monitor-up", 7)
			end
			return
		end
		local bridgeUrl = tostring(opts.BridgeUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if not bridgeUrl:match("^wss?://") then
			setStatus("Spotify bridge is not configured by the script owner", Color3.fromRGB(255, 105, 105))
			return
		end
		local url = bridgeUrl
			.. (bridgeUrl:find("?", 1, true) and "&" or "?")
			.. "code=" .. pairBox.Text .. "&role=game"
		local connect = websocketConnect()
		if not connect then
			setStatus("This executor has no WebSocket support", Color3.fromRGB(255, 105, 105))
			return
		end
		setStatus("Connecting...", Color3.fromRGB(255, 190, 90))
		if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("loader-circle") end
		task.spawn(function()
			local ok, result = pcall(connect, url)
			if not ok or not result then
				if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("link-2") end
				setStatus("Connection failed: " .. tostring(result), Color3.fromRGB(255, 105, 105))
				return
			end
			socket = result
			isConnected = true
			if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("copy") end
			local pageUrl = tostring(opts.ConnectUrl or "")
			local pairUrl = pageUrl .. (pageUrl:find("?", 1, true) and "&" or "?") .. "code=" .. pairBox.Text
			local copy = hasFn("setclipboard")
			if copy then pcall(copy, pairUrl) end
			setStatus(copy and "Player link copied — open it in your browser" or ("Open player page; code " .. pairBox.Text), Color3.fromRGB(30, 215, 96))
			if copy then
				spotifyNotify("initial_link", "Spotify Connect ready", "The player link was copied. Open it now and keep the browser tab running.", "success", "copy-check", 7, {
					{ Text = "Copy again", Callback = function() pcall(copy, pairUrl) end },
				})
			else
				spotifyNotify("manual_code", "Open Spotify Bridge", "Enter pairing code " .. pairBox.Text .. " on the player page.", "warning", "monitor-up", 7)
			end

			bindSocketEvent(socket.OnMessage, function(raw)
				local decoded
				local decodedOk = pcall(function() decoded = HttpService:JSONDecode(tostring(raw)) end)
				if not decodedOk or type(decoded) ~= "table" then return end
				if decoded.type == "state" or decoded.event == "state" then
					applyState(decoded)
				elseif decoded.type == "queue" then
					local playlist = decoded.playlist or {}
					currentPlaylistName = tostring(playlist.name or "Spotify playlist")
					local trackCount = tonumber(decoded.count) or 0
					setStatus(string.format("%s — %d tracks ready", currentPlaylistName, trackCount), Color3.fromRGB(30, 215, 96))
					spotifyNotify("queue_ready_" .. currentPlaylistName, "Playlist ready", string.format("%s loaded with %d tracks.", currentPlaylistName, trackCount), "success", "list-music", 4)
				elseif decoded.type == "ready" or decoded.event == "ready" then
					local message = tostring(decoded.message or "Spotify ready")
					setStatus(message, Color3.fromRGB(30, 215, 96))
					local lower = message:lower()
					if lower:find("press", 1, true) or lower:find("open", 1, true) or lower:find("tap", 1, true) then
						spotifyNotify("browser_action", "Browser action needed", "Open Spotify Bridge and press Play once to unlock remote controls.", "warning", "monitor-play", 7)
					end
				elseif decoded.type == "needs_browser" then
					local message = tostring(decoded.message or "Open the Spotify player tab once to continue playback")
					setStatus(message, Color3.fromRGB(255, 190, 90))
					spotifyNotify("browser_attention", "Spotify needs attention", message, "warning", "external-link", 7)
				elseif decoded.type == "error" or decoded.event == "error" then
					local message = tostring(decoded.message or decoded.error or "Spotify bridge error")
					setStatus(message, Color3.fromRGB(255, 105, 105))
					spotifyNotify("spotify_error_" .. message, "Spotify error", message, "error", "circle-x", 6)
				end
			end)
			bindSocketEvent(socket.OnClose, function()
				disconnectBridge(false)
			end)
			send("hello", { client = "NullUI", protocol = 1 })
		end)
	end

	jan:Add(connectBtn.MouseButton1Click:Connect(connectBridge))
	jan:Add(loadBtn.MouseButton1Click:Connect(function()
		local url = playlistBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if url == "" then
			setStatus("Paste a Spotify playlist link", Color3.fromRGB(255, 190, 90))
			return
		end
		if send("load_playlist", { url = url }) then
			setStatus("Playlist sent to Spotify", Color3.fromRGB(30, 215, 96))
			spotifyNotify("playlist_sent", "Open Spotify Bridge", "Open the browser site, wait for the playlist and press Play once. Then return to Roblox to control it here.", "warning", "external-link", 8)
		end
	end))
	local function searchPlaylist()
		local query = searchBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if query == "" then setStatus("Type a song or artist to search", Color3.fromRGB(255, 190, 90)); return end
		if send("search", { query = query }) then setStatus("Searching this playlist...", Color3.fromRGB(30, 215, 96)) end
	end
	jan:Add(searchBtn.MouseButton1Click:Connect(searchPlaylist))
	jan:Add(searchBox.FocusLost:Connect(function(enterPressed) if enterPressed then searchPlaylist() end end))
	jan:Add(shuffleBtn.MouseButton1Click:Connect(function() send("toggle_shuffle") end))
	jan:Add(previousBtn.MouseButton1Click:Connect(function() send("previous") end))
	jan:Add(playBtn.MouseButton1Click:Connect(function() send("play_pause") end))
	jan:Add(nextBtn.MouseButton1Click:Connect(function() send("next") end))
	jan:Add(repeatBtn.MouseButton1Click:Connect(function() send("cycle_repeat") end))
	local seekInput
	local function updateSeekPreview(screenX)
		if durationMs <= 0 or progressTrack.AbsoluteSize.X <= 0 then return end
		local alpha = math.clamp((screenX - progressTrack.AbsolutePosition.X) / progressTrack.AbsoluteSize.X, 0, 1)
		seekPreviewMs = math.floor(durationMs * alpha)
		progressFill.Size = UDim2.new(alpha, 0, 1, 0)
		progressKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
		seekBubble.Position = UDim2.new(math.clamp(alpha, 0.04, 0.96), 0, 0, -8)
		seekBubbleLabel.Text = formatTime(seekPreviewMs)
		timeLabel.Text = formatTime(seekPreviewMs)
	end
	jan:Add(progressHitbox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if durationMs <= 0 then return end
		seekDragging = true
		seekInput = input
		seekBubble.Visible = true
		updateSeekPreview(input.Position.X)
	end))
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not seekDragging then return end
		if input == seekInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			updateSeekPreview(input.Position.X)
		end
	end))
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if not seekDragging then return end
		if input ~= seekInput and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		updateSeekPreview(input.Position.X)
		seekDragging = false
		seekInput = nil
		seekBubble.Visible = false
		if send("seek", { positionMs = seekPreviewMs }) then
			progressMs = seekPreviewMs
			lastStateClock = os.clock()
		end
		renderProgress()
	end))

	jan:Add(function() disconnectBridge(true) end)
	dockBtn = self:AddDockButton({
		Icon = opts.Icon or "Lucide:music-2",
		Callback = function() panel.Toggle() end,
	})

	panel.Connect = connectBridge
	panel.Disconnect = disconnectBridge
	panel.Send = send
	panel.SetState = applyState
	if opts.BridgeUrl == nil or opts.BridgeUrl == "" then
		setStatus("Spotify bridge is not configured by the script owner", Color3.fromRGB(255, 190, 90))
	else
		setStatus("Tap Connect, then open the copied browser link", Color3.fromRGB(125, 130, 128))
	end
	return panel
end


end,
}
