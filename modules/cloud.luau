--!nonstrict
return {
Name = "cloud", API = 1,
Requires = {"chat-common"},
Install = function(context)
	local Corner = context.Corner
	local EnsureAssetsFolder = context.EnsureAssetsFolder
	local HttpService = context.HttpService
	local LocalPlayer = context.LocalPlayer
	local MeasureText = context.MeasureText
	local NullUI = context.NullUI
	local Players = context.Players
	local ResolveIcon = context.ResolveIcon
	local Stroke = context.Stroke
	local Tab = context.Tab
	local Tween = context.Tween
	local Window = context.Window
	local Z = context.Z
	local fn_isfile = context.fn_isfile
	local fn_readfile = context.fn_readfile
	local fn_writefile = context.fn_writefile
	local hasFn = context.hasFn
	local CreateChatComposer, CreateChatMessages, BindChatAutoscroll, ChatHeaderButton = context.Shared.CreateChatComposer, context.Shared.CreateChatMessages, context.Shared.BindChatAutoscroll, context.Shared.ChatHeaderButton
function Window:AddCloudPanel(opts)
	opts = opts or {}
	local service = opts.Service

	local tabObj = self:AddTab({
		Name   = opts.Name or "Cloud",
		Icon   = opts.Icon or "cloud",
		Hidden = opts.Hidden ~= false,
	})

	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)

	local mineGrid, publicGrid, localGrid
	local function relativeTime(timestamp)
		local seconds = math.max(0, os.time() - tonumber(timestamp or os.time()))
		if seconds < 60 then return "updated just now" end
		if seconds < 3600 then return "updated " .. math.floor(seconds / 60) .. "m ago" end
		if seconds < 86400 then return "updated " .. math.floor(seconds / 3600) .. "h ago" end
		return "updated " .. math.floor(seconds / 86400) .. "d ago"
	end

	local CloudTabs = {
		Local = tabObj:AddSubTab({ Name = "Local Configs", Icon = "Lucide:hard-drive" }),
		Mine = tabObj:AddSubTab({ Name = "Publish Public Config", Icon = "Lucide:cloud-cog" }),
		Explore = tabObj:AddSubTab({ Name = "Public Configs", Icon = "Lucide:cloud" }),
	}

	CloudTabs.Local:AddParagraph({
		Title = "Local Library",
		Icon = "Lucide:hard-drive",
		Text = "Private presets saved only on this device. Load, create and manage them without uploading anything.",
	})

	CloudTabs.Local:AddSection("Quick Actions", "Lucide:zap")
	CloudTabs.Local:AddButton({
		Text = "Save Current Settings Locally",
		Description = "Stays on this device only",
		Icon = "Lucide:save",
		Callback = function()
			NullUI:Modal({
				Title = "Save Config Locally",
				Text  = "Stays only on this device -- never sent anywhere.",
				ConfirmText = "Save",
				CancelText  = "Cancel",
				Window = self,
				Fields = {
					{ Key = "Name", Label = "Name", Placeholder = "Enter a name...", MaxLength = 60 },
					{ Key = "Description", Label = "Description (optional)", Type = "textarea",
						Placeholder = "What's different about this one?", MaxLength = 280 },
				},
				Callback = function(confirmed, values)
					if not confirmed then return end
					if not values.Name or values.Name:gsub("%s+", "") == "" then
						NullUI:Notify({ Title = "Local Save", Text = "Name can't be empty.", Type = "warning", Duration = 3 })
						return
					end
					local function saveNow()
						local ok, err = NullUI:SaveConfig(values.Name, { Description = values.Description })
						NullUI:Notify({
							Title = ok and "Saved" or "Could not save", Text = ok and "Saved locally." or tostring(err),
							Type = ok and "success" or "error", Duration = 3,
						})
						if ok and localGrid then localGrid.Refresh() end
					end
					if NullUI:GetConfigMeta(values.Name) then
						NullUI:Confirm({
							Title = "Overwrite \"" .. tostring(values.Name) .. "\"?",
							Text = "A local config already uses this name.", ConfirmText = "Overwrite", CancelText = "Cancel",
							Danger = true, Window = self,
							Callback = function(overwrite) if overwrite then saveNow() end end,
						})
					else
						saveNow()
					end
				end,
			})
		end,
	})

	localGrid = CloudTabs.Local:AddCardGrid({
		Title = "Local Configs",
		Height = 224,
		FixedHeight = true,
		Search = true,
		SearchPlaceholder = "Search local configs...",
		CardHeight = 68,
		AutoCardHeight = false,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = "No local configs saved yet.",
		ErrorText = "Your executor doesn't support local file access.",
		Fetch = function(state)
			local items, err = NullUI:ListConfigs()
			if err and #items == 0 then return nil, err end
			local query = string.lower(tostring(state and state.Query or ""))
			local out = {}
			for _, cfg in ipairs(items) do
				local searchable = string.lower(table.concat({
					tostring(cfg.Name or ""),
					tostring(cfg.Description or ""),
					table.concat(cfg.Tags or {}, " "),
				}, " "))
				if query ~= "" and not string.find(searchable, query, 1, true) then continue end

				local function loadLocalConfig()
					NullUI:Confirm({
						Title = "Load \"" .. tostring(cfg.Name) .. "\"?",
						Text = "This overwrites your current settings. A snapshot is kept for instant undo.",
						ConfirmText = "Load", CancelText = "Cancel", Window = self,
						Callback = function(confirmedLoad)
							if not confirmedLoad then return end
							local snapshot = NullUI:CreateSnapshot()
							local ok, loadErr = NullUI:LoadConfig(cfg.Name, false)
							if not ok then
								NullUI:Notify({ Title = "Could not load", Text = tostring(loadErr), Type = "error", Duration = 4 })
								return
							end
							NullUI:Notify({
								Title = "Loaded", Text = tostring(cfg.Name) .. " is now active.", Type = "success", Duration = 6,
								Actions = {{ Text = "Undo", Callback = function() NullUI:RestoreSnapshot(snapshot, false) end }},
							})
						end,
					})
				end

				local function renameLocalConfig()
					NullUI:Modal({
						Title = "Rename Config", Text = "Choose a new name for \"" .. tostring(cfg.Name) .. "\".",
						ConfirmText = "Rename", CancelText = "Cancel", Window = self,
						Fields = {{ Key = "Name", Label = "New name", Default = cfg.Name, MaxLength = 60 }},
						Callback = function(confirmed, values)
							if not confirmed then return end
							local newName = tostring(values.Name or ""):match("^%s*(.-)%s*$")
							if newName == "" then return end
							local existing = NullUI:GetConfigMeta(newName)
							if existing and newName ~= cfg.Name then
								NullUI:Notify({ Title = "Name already used", Text = "Choose another config name.", Type = "warning", Duration = 3 })
								return
							end
							local ok, renameErr = NullUI:RenameConfig(cfg.Name, newName)
							NullUI:Notify({ Title = ok and "Renamed" or "Could not rename", Text = ok and "Config name updated." or tostring(renameErr), Type = ok and "success" or "error", Duration = 3 })
							if ok and localGrid then localGrid.Refresh() end
						end,
					})
				end

				local function publishLocalConfig()
					if not service then
						NullUI:Notify({ Title = "Cloud", Text = "No cloud service configured.", Type = "warning", Duration = 3 })
						return
					end
					local saved, savedErr = NullUI:GetSavedConfig(cfg.Name)
					if not saved then
						NullUI:Notify({ Title = "Could not read config", Text = tostring(savedErr), Type = "error", Duration = 3 })
						return
					end
					local result, publishErr = service:Publish({ Name = cfg.Name, Description = cfg.Description, Tags = cfg.Tags }, saved.Data)
					NullUI:Notify({ Title = result and "Published" or "Could not publish", Text = result and "Config published successfully." or tostring(publishErr), Type = result and "success" or "error", Duration = 4 })
					if result then
						if mineGrid then mineGrid.Refresh() end
						if publicGrid then publicGrid.Refresh() end
					end
				end

				local function deleteLocalConfig()
					NullUI:Confirm({
						Title = "Delete \"" .. tostring(cfg.Name) .. "\"?", Text = "This local config will be permanently removed.",
						ConfirmText = "Delete", CancelText = "Cancel", Danger = true, Window = self,
						Callback = function(confirmed)
							if not confirmed then return end
							local ok, deleteErr = NullUI:DeleteConfig(cfg.Name)
							NullUI:Notify({ Title = ok and "Deleted" or "Could not delete", Text = ok and "Config removed." or tostring(deleteErr), Type = ok and "success" or "error", Duration = 3 })
							if ok and localGrid then localGrid.Refresh() end
						end,
					})
				end

				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = relativeTime(cfg.CreatedAt)
						.. ((cfg.Tags and #cfg.Tags > 0) and ("  •  " .. table.concat(cfg.Tags, ", ")) or ""),
					Icon = "Lucide:file-text",
					ActionIcon = "download",
					Callback = loadLocalConfig,
					SecondaryIcon = "trash-2",
					SecondaryCallback = deleteLocalConfig,
					SecondaryDanger = true,
				})
			end
			return out
		end,
	})

	local function publishFlow()
		if not service then
			NullUI:Notify({ Title = "Cloud", Text = "No cloud service configured.", Type = "warning", Duration = 3 })
			return
		end
		NullUI:Modal({
			Title = "New Config",
			ConfirmText = "Publish",
			CancelText = "Cancel",
			Window = self,
			Fields = {
				{ Key = "Name", Label = "Name", Placeholder = "Enter profile name...", MaxLength = 60 },
				{ Key = "Description", Label = "Description", Type = "textarea",
					Placeholder = "Enter profile's description...", MaxLength = 280 },
				{ Key = "Tags", Label = "Tags (optional)", Type = "tags",
					Placeholder = "Enter tags separated by commas..." },
			},
			Callback = function(confirmed, values)
				if not confirmed then return end
				local result, err = service:Publish({
					Name = values.Name,
					Description = values.Description,
					Tags = values.Tags,
				})
				NullUI:Notify({
					Title = result and "Published" or "Could not publish",
					Text  = result and "Your config is now public." or tostring(err),
					Type  = result and "success" or "error",
					Duration = 4,
				})
				if result then
					if mineGrid then mineGrid.Refresh() end
					if publicGrid then publicGrid.Refresh() end
				end
			end,
		})
	end

	CloudTabs.Mine:AddParagraph({
		Title = "My Cloud Library",
		Icon = "Lucide:cloud",
		Text = "Publish your current setup, review what you shared and remove old uploads from one place.",
	})

	CloudTabs.Mine:AddSection("Publishing", "Lucide:upload-cloud")
	CloudTabs.Mine:AddButton({
		Text = "Publish Current Settings",
		Description = "Share your current config publicly",
		Icon = "Lucide:upload-cloud",
		Callback = publishFlow,
	})

	mineGrid = CloudTabs.Mine:AddCardGrid({
		Title = "Your Configs",
		Height = 210,
		FixedHeight = true,
		Search = false,
		CardHeight = 104,
		AutoCardHeight = false,
		DescriptionHeight = 24,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = service and "You haven't published anything yet." or "No cloud service configured.",
		ErrorText = "Couldn't load your configs.",
		Fetch = function()
			if not service then
				return {}, nil
			end
			local items, err = service:ListMine()
			if not items then return nil, err end
			local out = {}
			for _, cfg in ipairs(items) do
				local function deletePublishedConfig()
					NullUI:Confirm({
						Title = "Delete \"" .. tostring(cfg.Name) .. "\"?",
						Text = "This removes it from the public library. This cannot be undone.",
						ConfirmText = "Delete", CancelText = "Cancel", Danger = true, Window = self,
						Callback = function(confirmedDelete)
							if not confirmedDelete then return end
							local ok, delErr = service:Delete(cfg.Id)
							NullUI:Notify({ Title = ok and "Deleted" or "Could not delete", Text = ok and "Config removed." or tostring(delErr), Type = ok and "success" or "error", Duration = 3 })
							if ok then
								if mineGrid then mineGrid.Refresh() end
								if publicGrid then publicGrid.Refresh() end
							end
						end,
					})
				end
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = cfg.CreatedAtText or "",
					Icon = "Lucide:cloud",
					Stats = {
						{ Icon = "thumbs-up", Text = tostring(cfg.Likes or 0) },
						{ Icon = "download", Text = tostring(cfg.Downloads or 0) },
					},
					Menu = {
						{ Text = "Delete publication", Icon = "trash-2", Danger = true, Callback = deletePublishedConfig },
					},
				})
			end
			return out
		end,
	})

	CloudTabs.Explore:AddParagraph({
		Title = "Community Library",
		Icon = "Lucide:compass",
		Text = "Discover public configs, compare popularity and apply a setup with an instant undo snapshot.",
	})

	CloudTabs.Explore:AddSection("Browse Configs", "Lucide:layout-grid")

	local SORT_MAP = { ["Top Rated"] = "top", ["Most Downloaded"] = "downloads", ["Newest"] = "new" }

	publicGrid = CloudTabs.Explore:AddCardGrid({
		Title = "Public Configs",
		Height = 230,
		FixedHeight = true,
		Sorts = { "Top Rated", "Most Downloaded", "Newest" },
		SearchPlaceholder = "Search config by name / tags...",
		CardHeight = 112,
		AutoCardHeight = false,
		DescriptionHeight = 24,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = "No public configs match your search.",
		ErrorText = "Couldn't reach the cloud service.",
		Fetch = function(state)
			if not service then return nil, "No cloud service configured." end
			local items, err = service:List({
				Query = state.Query,
				Sort = SORT_MAP[state.Sort] or "top",
				PageSize = state.PageSize,
			})
			if not items then return nil, err end
			local out = {}
			for _, cfg in ipairs(items) do
				local byline = cfg.OwnerName or "anonymous"
				if cfg.CreatedAtText then byline = byline .. " \226\128\162 " .. cfg.CreatedAtText end
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = byline,
					Icon = "Lucide:cloud-download",
					ActionIcon = "download",
					Stats = {
						{
							Icon = "thumbs-up",
							Text = tostring(cfg.Likes or 0),
							Callback = function()
								local liked, likeErr = service:Like(cfg.Id)
								if not liked then
									NullUI:Notify({
										Title = "Could not like",
										Text  = tostring(likeErr),
										Type  = "error",
										Duration = 3,
									})
									return
								end
								if publicGrid then publicGrid.Refresh() end
							end,
						},
						{ Icon = "download", Text = tostring(cfg.Downloads or 0) },
					},
					Callback = function()
						NullUI:Confirm({
							Title = "Apply \"" .. tostring(cfg.Name) .. "\"?",
							Text  = "This overwrites your current settings. A snapshot of what you have now "
								.. "is kept so you can undo it right after.",
							ConfirmText = "Apply",
							CancelText  = "Cancel",
							Window = self,
							Callback = function(confirmedApply)
								if not confirmedApply then return end
								local result, dlErr = service:Download(cfg.Id)
								if not result or not result.Data then
									NullUI:Notify({
										Title = "Could not apply",
										Text  = tostring(dlErr),
										Type  = "error",
										Duration = 4,
									})
									return
								end

								local snapshot = NullUI:CreateSnapshot()

								NullUI:SetConfig(result.Data, false)
								NullUI:Notify({
									Title = "Applied",
									Text  = tostring(cfg.Name) .. " is now active.",
									Type  = "success",
									Duration = 6,
									Actions = {
										{
											Text = "Undo",
											Callback = function()
												NullUI:RestoreSnapshot(snapshot, false)
												NullUI:Notify({
													Title = "Reverted",
													Text  = "Your previous settings are back.",
													Type  = "info",
													Duration = 3,
												})
											end,
										},
									},
								})

								if publicGrid then publicGrid.Refresh() end
								if opts.OnApplied then task.spawn(opts.OnApplied, cfg) end
							end,
						})
					end,
				})
			end
			return out
		end,
	})

	local lastRealTab = nil
	local function openPanel()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end

	return {
		Instance = tabObj._group,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		RefreshMine = function() if mineGrid then mineGrid.Refresh() end end,
		RefreshPublic = function() if publicGrid then publicGrid.Refresh() end end,
	}
end

function Window:AddGlobalChatPanel(opts)
	opts = opts or {}
	local service = opts.Service
	local jan = self._janitor

	local tabObj = self:AddTab({
		Name   = opts.Name or "Chat",
		Icon   = opts.Icon or "messages-square",
		Hidden = opts.Hidden ~= false,
	})
	tabObj._page.Visible = false
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end

	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)

	local INPUT_H, HEADER_H = 38, 38

	local panel = Instance.new("Frame")
	panel.Name = "GlobalChatPanel"
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
	titleRow.Size = UDim2.new(1, -136, 1, 0)
	titleRow.ZIndex = BASE_Z + 1
	titleRow.Parent = header

	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow

	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "messages-square")
	titleIcon.ImageColor3 = NullUI.Theme.Text
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = BASE_Z + 2
	titleIcon.Parent = titleRow

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = opts.Title or "Chat"
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
	controls.Size = UDim2.fromOffset(126, 22)
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

	local anonymousMode = opts.AnonymousByDefault ~= false
	local showTimestamps = true
	local notifySound = false
	local pollInterval = opts.PollInterval or 2.5

	local copyBtn, copyIcon = headerIconButton("copy", 1)
	local anonBtn, anonIcon = headerIconButton(anonymousMode and "eye-off" or "eye", 2)
	local clearBtn, clearIcon = headerIconButton("trash-2", 3)
	local settingsBtn, settingsIcon = headerIconButton("settings", 4)
	local closeBtn, closeIcon = headerIconButton("x", 5)

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

	local inputRow, pill, inputBox, sendBtn, sendIcon = CreateChatComposer(content, INPUT_H, BASE_Z, jan, opts.Placeholder or "Message everyone using this script...")

	local msgScroll, msgLayout = CreateChatMessages(content, panel, HEADER_H, INPUT_H, BASE_Z, jan)

	local order = 0
	local transcript = {}
	local timestampLabels = {}
	local scrollToBottom = BindChatAutoscroll(msgScroll, jan)

	local AVATAR = 26

	local function addBubble(msg, isOwn)
		order = order + 1
		local text = tostring(msg.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then return end

		local row = Instance.new("Frame")
		row.Name = "ChatRow"
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
		rowLayout.HorizontalAlignment = isOwn and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row

		local isAnon = not msg.UserId or msg.UserId == 0

		local avatar = Instance.new("Frame")
		avatar.Name = "Avatar"

		avatar.BackgroundColor3 = isAnon and Color3.fromRGB(196, 143, 105) or NullUI.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = isOwn and 2 or 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)

		if isAnon then
			local anonIconImg = Instance.new("ImageLabel")
			anonIconImg.BackgroundTransparency = 1
			anonIconImg.ImageTransparency = 1
			anonIconImg.Image = ResolveIcon("user-round")
			anonIconImg.ImageColor3 = Color3.fromRGB(90, 61, 40)
			anonIconImg.Size = UDim2.fromOffset(15, 15)
			anonIconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			anonIconImg.Position = UDim2.fromScale(0.5, 0.5)
			anonIconImg.ZIndex = BASE_Z + 3
			anonIconImg.Parent = avatar
			Tween(anonIconImg, { ImageTransparency = 0 }, 0.16)
		else
			local avatarImg = Instance.new("ImageLabel")
			avatarImg.BackgroundTransparency = 1
			avatarImg.ImageTransparency = 1
			avatarImg.ScaleType = Enum.ScaleType.Crop
			avatarImg.Size = UDim2.fromScale(1, 1)
			avatarImg.ZIndex = BASE_Z + 3
			avatarImg.Parent = avatar
			Corner(avatarImg, AVATAR / 2)
			Tween(avatarImg, { ImageTransparency = 0 }, 0.16)
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					msg.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
				if ok and content and avatarImg.Parent then
					avatarImg.Image = content
				end
			end)
		end

		local H_PAD, V_PAD = 10, 8
		local BUBBLE_MAX_WIDTH = 240

		local MIN_BUBBLE_WIDTH = 64
		local naturalW = MeasureText(text, 13, 10000)
		local bubbleWidth = math.min(naturalW, BUBBLE_MAX_WIDTH - H_PAD * 2) + H_PAD * 2
		bubbleWidth = math.max(bubbleWidth, MIN_BUBBLE_WIDTH)
		if msgScroll.AbsoluteSize.X > 0 then
			bubbleWidth = math.min(bubbleWidth, math.max(160, msgScroll.AbsoluteSize.X - 20))
		end

		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.BackgroundColor3 = isOwn and NullUI.Theme.Accent or Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.ClipsDescendants = true
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
		bubble.LayoutOrder = isOwn and 1 or 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local bubbleStroke = Stroke(bubble, Color3.new(1, 1, 1), 1, 1)

		local bubblePad = Instance.new("UIPadding")
		bubblePad.PaddingTop = UDim.new(0, V_PAD)
		bubblePad.PaddingBottom = UDim.new(0, V_PAD)
		bubblePad.PaddingLeft = UDim.new(0, H_PAD)
		bubblePad.PaddingRight = UDim.new(0, H_PAD)
		bubblePad.Parent = bubble

		local bubbleLayout = Instance.new("UIListLayout")
		bubbleLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bubbleLayout.Parent = bubble

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = NullUI.Theme.FontRegular
		label.Text = text
		label.TextColor3 = NullUI.Theme.Text
		label.TextTransparency = 1
		label.TextSize = 13
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.LineHeight = 1.3
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.new(1, 0, 0, 16)
		label.LayoutOrder = 1
		label.ZIndex = BASE_Z + 3
		label.Parent = bubble

		if msg.CreatedAt then
			local timeLbl = Instance.new("TextLabel")
			timeLbl.BackgroundTransparency = 1
			timeLbl.FontFace = NullUI.Theme.FontRegular
			timeLbl.Text = os.date("%H:%M", math.floor(msg.CreatedAt / 1000))
			timeLbl.TextColor3 = isOwn and Color3.new(1, 1, 1) or NullUI.Theme.TextDim
			timeLbl.TextTransparency = isOwn and 0.5 or 0.4
			timeLbl.TextSize = 10
			timeLbl.TextXAlignment = Enum.TextXAlignment.Left
			timeLbl.AutomaticSize = Enum.AutomaticSize.Y
			timeLbl.Size = UDim2.new(1, 0, 0, 12)
			timeLbl.LayoutOrder = 2
			timeLbl.ZIndex = BASE_Z + 3

			timeLbl.Visible = showTimestamps
			timeLbl.Parent = bubble
			table.insert(timestampLabels, timeLbl)
		end

		if not isOwn and msg.Id and service then
			local reportBtn = Instance.new("TextButton")
			reportBtn.Text = ""
			reportBtn.AutoButtonColor = false
			reportBtn.BackgroundColor3 = Color3.new(1, 1, 1)
			reportBtn.BackgroundTransparency = 1
			reportBtn.BorderSizePixel = 0
			reportBtn.Size = UDim2.fromOffset(20, 20)
			reportBtn.LayoutOrder = 3
			reportBtn.ZIndex = BASE_Z + 2
			reportBtn.Parent = row
			Corner(reportBtn, 6)

			local reportIcon = Instance.new("ImageLabel")
			reportIcon.BackgroundTransparency = 1
			reportIcon.ImageTransparency = 1
			reportIcon.Image = ResolveIcon("flag")
			reportIcon.ImageColor3 = NullUI.Theme.TextDim
			reportIcon.Size = UDim2.fromOffset(11, 11)
			reportIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			reportIcon.Position = UDim2.fromScale(0.5, 0.5)
			reportIcon.ZIndex = BASE_Z + 3
			reportIcon.Parent = reportBtn

			jan:Add(row.MouseEnter:Connect(function()
				Tween(reportIcon, { ImageTransparency = 0.3 }, 0.12)
			end))
			jan:Add(row.MouseLeave:Connect(function()
				Tween(reportIcon, { ImageTransparency = 1 }, 0.12)
			end))
			jan:Add(reportBtn.MouseEnter:Connect(function()
				Tween(reportBtn, { BackgroundTransparency = 0.88 }, 0.1)
				Tween(reportIcon, { ImageColor3 = NullUI.Theme.Danger, ImageTransparency = 0 }, 0.1)
			end))
			jan:Add(reportBtn.MouseLeave:Connect(function()
				Tween(reportBtn, { BackgroundTransparency = 1 }, 0.1)
				Tween(reportIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.1)
			end))
			jan:Add(reportBtn.MouseButton1Click:Connect(function()
				NullUI:Confirm({
					Title = "Report this message?",
					Text  = "Hides it for everyone once enough people report it.",
					ConfirmText = "Report",
					CancelText  = "Cancel",
					Danger = true,
					Window = self,
					Callback = function(confirmed)
						if not confirmed then return end
						local ok, err = service:ReportChatMessage(msg.Id)
						NullUI:Notify({
							Title = ok and "Reported" or "Could not report",
							Text  = ok and "Thanks -- our filters will take it from here." or tostring(err),
							Type  = ok and "success" or "error",
							Duration = 3,
						})
					end,
				})
			end))
		end

		local avatarFinalTransparency = isOwn and 0.85 or 0.82
		local bubbleFinalTransparency = isOwn and 0.72 or 0.9
		local strokeFinalTransparency = isOwn and 0.8 or 0.9
		Tween(avatar, { BackgroundTransparency = avatarFinalTransparency }, 0.16)
		Tween(bubble, { BackgroundTransparency = bubbleFinalTransparency }, 0.16)
		Tween(bubbleStroke, { Transparency = strokeFinalTransparency }, 0.16)
		Tween(label, { TextTransparency = 0 }, 0.16)
		Tween(rowScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		scrollToBottom()
		table.insert(transcript, (isOwn and "You" or "Someone") .. ": " .. text)
	end

	jan:Add(copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard or #transcript == 0 then return end
		pcall(setclipboard, table.concat(transcript, "\n"))
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.15)
			end
		end)
	end))

	local seenIds = { [0] = true }
	local lastSeenId = 0

	local function trySend()
		local text = inputBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" or not service then return end
		inputBox.Text = ""
		local sendUserId = anonymousMode and 0 or LocalPlayer.UserId
		task.spawn(function()
			local result, err = service:SendChatMessage(sendUserId, text)
			if not result then
				NullUI:Notify({ Title = "Chat", Text = tostring(err), Type = "error", Duration = 3 })
				return
			end
			seenIds[result.Id] = true
			if result.Id > lastSeenId then lastSeenId = result.Id end
			addBubble({ UserId = sendUserId, Text = text, CreatedAt = os.time() * 1000 }, true)
		end)
	end

	jan:Add(sendBtn.MouseButton1Click:Connect(trySend))
	jan:Add(inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then trySend() end
	end))
	jan:Add(anonBtn.MouseButton1Click:Connect(function()
		anonymousMode = not anonymousMode
		anonIcon.Image = ResolveIcon(anonymousMode and "eye-off" or "eye")
		NullUI:Notify({
			Title = "Chat",
			Text  = anonymousMode
				and "Anonymous mode on -- new messages won't reveal your avatar."
				or "Anonymous mode off -- new messages show your avatar.",
			Type  = "info",
			Duration = 3,
		})
	end))
	jan:Add(clearBtn.MouseButton1Click:Connect(function()

		for _, child in ipairs(msgScroll:GetChildren()) do
			if child.Name == "ChatRow" then child:Destroy() end
		end
		table.clear(transcript)
		table.clear(timestampLabels)
	end))
	jan:Add(closeBtn.MouseButton1Click:Connect(function()
		if self._currentTab == tabObj then
			if self._tabs[1] and self._tabs[1] ~= tabObj then self._tabs[1]._select() end
		end
	end))

	local settingsPopup
	local function closeSettingsPopup()
		if settingsPopup then
			settingsPopup:Destroy()
			settingsPopup = nil
		end
	end

	local function openSettingsPopup()
		if settingsPopup then closeSettingsPopup(); return end

		local popup = Instance.new("Frame")
		popup.Name = "ChatSettingsPopup"
		popup.BackgroundColor3 = NullUI.Theme.Surface
		popup.BackgroundTransparency = 0.05
		popup.BorderSizePixel = 0
		popup.AnchorPoint = Vector2.new(1, 0)
		popup.Position = UDim2.new(1, 0, 0, HEADER_H + 4)
		popup.Size = UDim2.new(0, 190, 0, 0)
		popup.AutomaticSize = Enum.AutomaticSize.Y
		popup.ClipsDescendants = true
		popup.ZIndex = BASE_Z + 10
		popup.Parent = panel
		Corner(popup, 10)
		local popupStroke = Stroke(popup, Color3.new(1, 1, 1), 1, 0.88)

		local popupPad = Instance.new("UIPadding")
		popupPad.PaddingTop = UDim.new(0, 10)
		popupPad.PaddingBottom = UDim.new(0, 10)
		popupPad.PaddingLeft = UDim.new(0, 12)
		popupPad.PaddingRight = UDim.new(0, 12)
		popupPad.Parent = popup

		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, 8)
		popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		popupLayout.Parent = popup

		local function toggleRow(order, label, getValue, onToggle)
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 20)
			row.LayoutOrder = order
			row.ZIndex = BASE_Z + 11
			row.Parent = popup

			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = NullUI.Theme.FontRegular
			lbl.Text = label
			lbl.TextColor3 = NullUI.Theme.Text
			lbl.TextSize = 12
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Size = UDim2.new(1, -30, 1, 0)
			lbl.ZIndex = BASE_Z + 12
			lbl.Parent = row

			local check = Instance.new("TextButton")
			check.Text = ""
			check.AutoButtonColor = false
			check.BackgroundColor3 = Color3.new(1, 1, 1)
			check.BackgroundTransparency = getValue() and 0.7 or 0.92
			check.BorderSizePixel = 0
			check.AnchorPoint = Vector2.new(1, 0.5)
			check.Position = UDim2.new(1, 0, 0.5, 0)
			check.Size = UDim2.fromOffset(20, 20)
			check.ZIndex = BASE_Z + 12
			check.Parent = row
			Corner(check, 6)

			local checkIcon = Instance.new("ImageLabel")
			checkIcon.BackgroundTransparency = 1
			checkIcon.Image = ResolveIcon("check")
			checkIcon.ImageColor3 = NullUI.Theme.Accent
			checkIcon.ImageTransparency = getValue() and 0 or 1
			checkIcon.Size = UDim2.fromOffset(11, 11)
			checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			checkIcon.Position = UDim2.fromScale(0.5, 0.5)
			checkIcon.ZIndex = BASE_Z + 13
			checkIcon.Parent = check

			jan:Add(check.MouseButton1Click:Connect(function()
				local newValue = onToggle()
				Tween(check, { BackgroundTransparency = newValue and 0.7 or 0.92 }, 0.12)
				Tween(checkIcon, { ImageTransparency = newValue and 0 or 1 }, 0.12)
			end))
		end

		toggleRow(1, "Show timestamps", function() return showTimestamps end, function()
			showTimestamps = not showTimestamps
			for _, lbl in ipairs(timestampLabels) do
				if lbl.Parent then lbl.Visible = showTimestamps end
			end
			return showTimestamps
		end)
		toggleRow(2, "Sound on new message", function() return notifySound end, function()
			notifySound = not notifySound
			return notifySound
		end)
		toggleRow(3, "Fast updates (1s)", function() return pollInterval <= 1 end, function()
			pollInterval = (pollInterval <= 1) and (opts.PollInterval or 2.5) or 1
			return pollInterval <= 1
		end)

		settingsPopup = popup
	end

	jan:Add(settingsBtn.MouseButton1Click:Connect(function()
		if settingsPopup then closeSettingsPopup() else openSettingsPopup() end
	end))

	local notifySoundInstance = Instance.new("Sound")
	notifySoundInstance.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	notifySoundInstance.Volume = 0.5
	notifySoundInstance.Parent = panel

	if service then
		task.spawn(function()
			local backlog = service:PollChatMessages(0)
			if backlog then
				local historyLimit = opts.HistoryLimit or 3
				local startIdx = math.max(1, #backlog - historyLimit + 1)
				for i = startIdx, #backlog do
					local m = backlog[i]
					if not seenIds[m.Id] then
						seenIds[m.Id] = true
						addBubble(m, m.UserId == LocalPlayer.UserId)
					end
					if m.Id > lastSeenId then lastSeenId = m.Id end
				end
			end
			while panel and panel.Parent do
				task.wait(pollInterval)
				local newMsgs = service:PollChatMessages(lastSeenId)
				if newMsgs then
					for _, m in ipairs(newMsgs) do
						if not seenIds[m.Id] then
							seenIds[m.Id] = true
							local isOwn = m.UserId == LocalPlayer.UserId
							addBubble(m, isOwn)

							if notifySound and not isOwn and notifySoundInstance.Parent then
								notifySoundInstance:Play()
							end
						end
						if m.Id > lastSeenId then lastSeenId = m.Id end
					end
				end
			end
		end)
	end

	local lastRealTab = nil
	local function openPanel()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end

	return {
		Instance = panel,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		Destroy = function() panel:Destroy() end,
	}
end

local CLOUD_IDENTITY_PATH = "NullUI/cloud_identity.json"

local function LoadCloudIdentity()
	if fn_isfile and fn_readfile then
		local existsOk, exists = pcall(fn_isfile, CLOUD_IDENTITY_PATH)
		if existsOk and exists then
			local ok, raw = pcall(fn_readfile, CLOUD_IDENTITY_PATH)
			if ok then
				local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
				if decodeOk and type(decoded) == "table" and decoded.Id then
					decoded.Tokens = decoded.Tokens or {}
					return decoded
				end
			end
		end
	end
	return nil
end

local function SaveCloudIdentity(identity)
	if not fn_writefile then return end
	EnsureAssetsFolder()
	pcall(fn_writefile, CLOUD_IDENTITY_PATH, HttpService:JSONEncode(identity))
end

local function GetOrCreateCloudIdentity()
	local identity = LoadCloudIdentity()
	if identity then return identity end
	identity = { Id = HttpService:GenerateGUID(false), Tokens = {} }
	SaveCloudIdentity(identity)
	return identity
end

local CLOUD_PUBLISH_COOLDOWN = 15
local LastCloudPublishAt = 0

function NullUI:CloudService(opts)
	opts = opts or {}
	local baseUrl = opts.BaseUrl
	local scriptId = opts.Script or "default"
	local identity = GetOrCreateCloudIdentity()
	local httpRequest = (syn and syn.request) or http_request or request

	local function apiRequest(method, path, body, extraHeaders)
		if not httpRequest then
			return nil, "Your executor doesn't support HTTP requests."
		end
		if not baseUrl or baseUrl == "" then
			return nil, "No cloud BaseUrl configured -- point CloudService's BaseUrl at your own backend."
		end

		local headers = {
			["Content-Type"] = "application/json",
			["X-NullUI-Identity"] = identity.Id,
			["X-NullUI-Script"] = scriptId,
		}
		if extraHeaders then
			for k, v in pairs(extraHeaders) do headers[k] = v end
		end

		local ok, res = pcall(httpRequest, {
			Url = baseUrl .. path,
			Method = method,
			Headers = headers,
			Body = body and HttpService:JSONEncode(body) or nil,
		})
		if not ok then return nil, tostring(res) end

		if res.StatusCode and (res.StatusCode < 200 or res.StatusCode >= 300) then
			local message = res.Body
			local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if decodeOk and type(decoded) == "table" and decoded.error then
				message = tostring(decoded.error)
			end
			return nil, "HTTP " .. tostring(res.StatusCode) .. ": " .. tostring(message)
		end

		if res.Body == nil or res.Body == "" then return {}, nil end
		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not decodeOk then return nil, "Failed to decode response." end
		return decoded, nil
	end

	local api = { Identity = identity.Id }

	function api:List(state)
		state = state or {}
		local query = "?sort=" .. HttpService:UrlEncode(state.Sort or "top")
		if state.Query and state.Query ~= "" then
			query = query .. "&q=" .. HttpService:UrlEncode(state.Query)
		end
		if state.Cursor then
			query = query .. "&cursor=" .. HttpService:UrlEncode(tostring(state.Cursor))
		end
		query = query .. "&limit=" .. tostring(state.PageSize or 20)

		local decoded, err = apiRequest("GET", "/configs" .. query)
		if not decoded then return nil, err end
		return decoded.Items or {}, decoded.NextCursor
	end

	function api:ListMine()
		local decoded, err = apiRequest("GET", "/configs/mine")
		if not decoded then return nil, err end
		return decoded.Items or {}
	end

	function api:GetByShareCode(shareCode)
		return apiRequest("GET", "/configs/code/" .. HttpService:UrlEncode(tostring(shareCode)))
	end

	function api:Publish(meta, data)
		meta = meta or {}
		local now = os.clock()
		if now - LastCloudPublishAt < CLOUD_PUBLISH_COOLDOWN then
			return nil, string.format(
				"Please wait %ds before publishing again.",
				math.ceil(CLOUD_PUBLISH_COOLDOWN - (now - LastCloudPublishAt))
			)
		end

		local cleanName, nameBlocked = NullUI:SanitizeText(meta.Name, { MaxLength = 60 })
		if nameBlocked or cleanName == "" then
			return nil, "Name was empty or blocked by the content filter."
		end
		local cleanDesc, descBlocked = NullUI:SanitizeText(meta.Description or "", { MaxLength = 280 })
		if descBlocked then
			return nil, "Description was blocked by the content filter."
		end

		local cleanTags = {}
		for _, tag in ipairs(meta.Tags or {}) do
			local cleanTag = NullUI:SanitizeText(tag, { MaxLength = 24 })
			if cleanTag ~= "" then table.insert(cleanTags, cleanTag) end
			if #cleanTags >= 8 then break end
		end

		LastCloudPublishAt = now

		local decoded, err = apiRequest("POST", "/configs", {
			Name = cleanName,
			Description = cleanDesc,
			Tags = cleanTags,
			Data = data or NullUI:GetConfig(),
		})
		if not decoded then return nil, err end

		if decoded.Id and decoded.OwnerToken then
			identity.Tokens[decoded.Id] = decoded.OwnerToken
			SaveCloudIdentity(identity)
		end
		return decoded
	end

	function api:Delete(id)
		local token = identity.Tokens[id]
		if not token then
			return false, "You don't have publish rights for this config on this device."
		end
		local decoded, err = apiRequest("DELETE", "/configs/" .. id, nil, {
			["X-NullUI-Owner-Token"] = token,
		})
		if not decoded then return false, err end
		identity.Tokens[id] = nil
		SaveCloudIdentity(identity)
		return true
	end

	function api:Like(id)
		local decoded, err = apiRequest("POST", "/configs/" .. id .. "/like")
		if not decoded then return false, err end
		return true
	end

	function api:Download(id)
		return apiRequest("POST", "/configs/" .. id .. "/download")
	end

	function api:SendChatMessage(userId, text)
		return apiRequest("POST", "/chat/send", { UserId = userId, Text = text })
	end

	function api:PollChatMessages(sinceId)
		local decoded, err = apiRequest("GET", "/chat?since=" .. tostring(sinceId or 0))
		if not decoded then return nil, err end
		return decoded.Messages or {}
	end

	function api:ReportChatMessage(messageId)
		local decoded, err = apiRequest("POST", "/chat/" .. tostring(messageId) .. "/report")
		if not decoded then return false, err end
		return true
	end

	function api:Heartbeat(payload)
		local decoded, err = apiRequest("POST", "/presence/heartbeat", payload)
		if not decoded then return false, err end
		return true
	end

	function api:GetActiveCount()
		local decoded, err = apiRequest("GET", "/presence/count")
		if not decoded then return nil, err end
		return decoded.Count or 0
	end

	function api:GetLeaderboard(limit)
		local decoded, err = apiRequest("GET", "/presence/leaderboard?limit=" .. tostring(limit or 10))
		if not decoded then return nil, err end
		return decoded.Items or {}
	end

	return api
end


end,
}
