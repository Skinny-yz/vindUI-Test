--!nonstrict
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")
local GuiService        = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local IsMobileDevice = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local NullUI = {}
NullUI.__index = NullUI
NullUI.Version = "2.9.0-modular"
NullUI.Flags = {}
NullUI._Windows = {}

local function GetGlobalTable()
	local ok, g = pcall(function()
		if getgenv then return getgenv() end
		return _G
	end)
	return (ok and g) or _G
end

do
	local globalTable = GetGlobalTable()
	local previousUnload = globalTable.__NullUI_Unload
	globalTable.__NullUI_Unload = nil
	if type(previousUnload) == "function" then
		pcall(previousUnload)
	end
end

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	return setmetatable({ _items = {}, _dead = false }, Janitor)
end

function Janitor:Add(item)
	if self._dead then
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		end
		return item
	end
	table.insert(self._items, item)
	return item
end

function Janitor:Destroy()
	if self._dead then return end
	self._dead = true
	for i = #self._items, 1, -1 do
		local item = self._items[i]
		self._items[i] = nil
		local t = typeof(item)
		if t == "RBXScriptConnection" then
			pcall(function() item:Disconnect() end)
		elseif t == "Instance" then
			pcall(function() item:Destroy() end)
		elseif t == "function" then
			pcall(item)
		elseif t == "table" and type(item.Destroy) == "function" then
			pcall(function() item:Destroy() end)
		end
	end
end

local LibJanitor = Janitor.new()

local UIJobs = {}
local function ScheduleUI(key, callback) UIJobs[key] = callback end
LibJanitor:Add(RunService.Heartbeat:Connect(function()
	local batch = UIJobs
	UIJobs = {}
	for _, callback in pairs(batch) do
		local ok, err = pcall(callback)
		if not ok then warn("VindUI layout: " .. tostring(err)) end
	end
end))
LibJanitor:Add(function() table.clear(UIJobs) end)

local function MakeSignal()
	local listeners = {}
	return {
		Fire = function(...)
			for _, fn in ipairs(table.clone(listeners)) do
				task.spawn(fn, ...)
			end
		end,
		Connect = function(fn)
			table.insert(listeners, fn)
			return {
				Disconnect = function()
					local i = table.find(listeners, fn)
					if i then table.remove(listeners, i) end
				end,
			}
		end,
		Clear = function()
			table.clear(listeners)
		end,
	}
end

local function SafeClamp(value, lo, hi)
	if hi < lo then return lo end
	return math.clamp(value, lo, hi)
end

local function SafeAlpha(value, min, max)
	local range = max - min
	if range == 0 then return 0 end
	return math.clamp((value - min) / range, 0, 1)
end

local function SnapToIncrement(raw, min, max, increment)
	if increment <= 0 then increment = 1 end
	local snapped = math.floor((raw - min) / increment + 0.5) * increment + min
	snapped = math.clamp(snapped, min, max)
	local decimals = 0
	local probe = increment
	while decimals < 6 and math.abs(probe - math.floor(probe + 0.5)) > 1e-9 do
		probe = probe * 10
		decimals = decimals + 1
	end
	local factor = 10 ^ decimals
	return math.floor(snapped * factor + (snapped >= 0 and 0.5 or -0.5)) / factor
end

local function FormatNumber(v)
	if math.abs(v - math.floor(v + 0.5)) < 1e-9 then
		return tostring(math.floor(v + 0.5))
	end
	return string.format("%.4g", v)
end

local ACRYLIC_DOF_NAME = "NullUI_AcrylicDOF"
local ACRYLIC_DISTANCE = 0.001
local ACRYLIC_TRANSPARENCY = 0.98
local AcrylicDOF = nil
local AcrylicControllers = {}
local CameraConnections = {}
local AcrylicShuttingDown = false

NullUI.Config = { Blur = true, MaxNotifications = 5 }

local function DisconnectCameraSignals()
	for i = #CameraConnections, 1, -1 do
		CameraConnections[i]:Disconnect()
		CameraConnections[i] = nil
	end
end

local function EnsureAcrylicDOF()
	if AcrylicDOF and AcrylicDOF.Parent then return AcrylicDOF end
	local stale = Lighting:FindFirstChild(ACRYLIC_DOF_NAME)
	if stale then stale:Destroy() end

	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = ACRYLIC_DOF_NAME
	dof.FarIntensity = 0
	dof.FocusDistance = 0.05
	dof.InFocusRadius = 0.1
	dof.NearIntensity = 1
	dof.Enabled = false
	dof.Parent = Lighting
	AcrylicDOF = dof
	LibJanitor:Add(dof)
	return dof
end

local function RefreshAcrylicEffect()
	if AcrylicShuttingDown then return end
	local dof = EnsureAcrylicDOF()
	dof.Enabled = NullUI.Config.Blur ~= false and #AcrylicControllers > 0
end

local function UpdateAllAcrylic()
	for index = #AcrylicControllers, 1, -1 do
		local controller = AcrylicControllers[index]
		if controller.Destroyed then
			table.remove(AcrylicControllers, index)
		else
			controller:Update()
		end
	end
end

local function BindAcrylicCamera(camera)
	DisconnectCameraSignals()
	if not camera then return end

	local function connect(property)
		table.insert(CameraConnections,
			camera:GetPropertyChangedSignal(property):Connect(UpdateAllAcrylic))
	end
	connect("CFrame")
	connect("ViewportSize")
	connect("FieldOfView")
	UpdateAllAcrylic()
end

local function CreateWindowAcrylic(guiObject)
	local folder = Instance.new("Folder")
	folder.Name = "NullUI_AcrylicWindow"

	local part = Instance.new("Part")
	part.Name = "Glass"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Glass
	part.Color = Color3.new(0, 0, 0)
	part.Reflectance = 0
	part.Size = Vector3.new(1, 1, 0.001)
	part.Transparency = 1
	part.Parent = folder

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "AcrylicMesh"
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Offset = Vector3.new(0, 0, -0.000001)
	mesh.Scale = Vector3.new(1, 1, 0.001)
	mesh.Parent = part

	local controller = {
		Gui = guiObject,
		Folder = folder,
		Part = part,
		Mesh = mesh,
		Connections = {},
		Destroyed = false,
	}

	function controller:Update()
		if self.Destroyed then return end
		local camera = workspace.CurrentCamera
		local gui = self.Gui
		if not camera or not gui or not gui.Parent then
			self.Part.Transparency = 1
			return
		end

		if self.Folder.Parent ~= camera then
			self.Folder.Parent = camera
		end

		local size = gui.AbsoluteSize
		local visible = NullUI.Config.Blur ~= false
			and gui.Visible and size.X > 2 and size.Y > 2
		self.Part.Transparency = visible and ACRYLIC_TRANSPARENCY or 1
		if not visible then self._lastGeometry = nil; return end
  local renderPose = camera:GetRenderCFrame()
  local last = self._lastGeometry
  if last and last.Camera == camera and last.Pose == renderPose
   and last.Size == size and last.Position == gui.AbsolutePosition
   and last.Viewport == camera.ViewportSize and last.Fov == camera.FieldOfView then return end
  self._lastGeometry = {Camera = camera, Pose = renderPose, Size = size,
   Position = gui.AbsolutePosition, Viewport = camera.ViewportSize, Fov = camera.FieldOfView}

		local edgeInset = math.clamp(camera.ViewportSize.Y * 0.012, 8, 18)
		local position = gui.AbsolutePosition + Vector2.new(edgeInset, edgeInset)
		local panelSize = Vector2.new(
			math.max(1, size.X - edgeInset * 2),
			math.max(1, size.Y - edgeInset * 2)
		)

		local function ScreenToWorld(point)
			local ray = camera:ScreenPointToRay(point.X, point.Y)
			return ray.Origin + ray.Direction * ACRYLIC_DISTANCE
		end

		local topLeft3D = ScreenToWorld(position)
		local topRight3D = ScreenToWorld(position + Vector2.new(panelSize.X, 0))
		local bottomRight3D = ScreenToWorld(position + panelSize)
		local width = (topRight3D - topLeft3D).Magnitude
		local height = (bottomRight3D - topRight3D).Magnitude
		local renderCFrame = renderPose

		self.Part.CFrame = CFrame.fromMatrix(
			(topLeft3D + bottomRight3D) / 2,
			renderCFrame.XVector,
			renderCFrame.YVector,
			renderCFrame.ZVector
		)
		self.Mesh.Scale = Vector3.new(width, height, 0.001)
	end

	function controller:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		for _, connection in ipairs(self.Connections) do
			connection:Disconnect()
		end
		table.clear(self.Connections)
		local index = table.find(AcrylicControllers, self)
		if index then table.remove(AcrylicControllers, index) end
		if self.Folder then self.Folder:Destroy() end
		RefreshAcrylicEffect()
	end

	for _, property in ipairs({ "AbsolutePosition", "AbsoluteSize", "Visible" }) do
		table.insert(controller.Connections,
			guiObject:GetPropertyChangedSignal(property):Connect(function()
				controller:Update()
			end))
	end
	table.insert(controller.Connections, guiObject.AncestryChanged:Connect(function()
		if not guiObject.Parent then controller:Destroy() end
	end))

	table.insert(AcrylicControllers, controller)
	RefreshAcrylicEffect()
	controller:Update()
	return controller
end

BindAcrylicCamera(workspace.CurrentCamera)
LibJanitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	BindAcrylicCamera(workspace.CurrentCamera)
end))
LibJanitor:Add(function()
	DisconnectCameraSignals()
end)

function NullUI:SetBlurEnabled(enabled)
	NullUI.Config.Blur = enabled and true or false
	RefreshAcrylicEffect()
	UpdateAllAcrylic()
end

local function DestroyAllAcrylicControllers()
	for index = #AcrylicControllers, 1, -1 do
		AcrylicControllers[index]:Destroy()
	end
	table.clear(AcrylicControllers)
end

local ASSETS_FOLDER = "NullUI/Assets"

local function hasFn(name)
	local ok, fn = pcall(function()
		if getgenv then
			local v = getgenv()[name]
			if type(v) == "function" then return v end
		end
		if getfenv then
			local v = getfenv(1)[name]
			if type(v) == "function" then return v end
		end
		return _G[name]
	end)
	if ok and type(fn) == "function" then return fn end
	return nil
end

local fn_isfolder    = hasFn("isfolder")
local fn_makefolder  = hasFn("makefolder")
local fn_isfile      = hasFn("isfile")
local fn_writefile   = hasFn("writefile")
local fn_readfile    = hasFn("readfile")
local fn_delfile     = hasFn("delfile")
local fn_listfiles   = hasFn("listfiles")
local fn_customasset = hasFn("getcustomasset") or hasFn("getsynasset")

local function EnsureAssetsFolder()
	if not (fn_isfolder and fn_makefolder) then return false end
	local ok = pcall(function()
		if not fn_isfolder("NullUI") then fn_makefolder("NullUI") end
		if not fn_isfolder(ASSETS_FOLDER) then fn_makefolder(ASSETS_FOLDER) end
	end)
	return ok
end

local function PrivateTabFlagPath(name)
	local safe = tostring(name or ""):gsub("[^%w_%-]", "_")
	return "NullUI/PrivateTab_" .. safe .. ".remember"
end

local function IsPrivateTabRemembered(name)
	if not fn_isfile then return false end
	local ok, exists = pcall(fn_isfile, PrivateTabFlagPath(name))
	return ok and exists == true
end

local function SetPrivateTabRemembered(name, remember)
	local path = PrivateTabFlagPath(name)
	if remember then
		if not fn_writefile then return end
		EnsureAssetsFolder()
		pcall(fn_writefile, path, "1")
	else
		if not (fn_isfile and fn_delfile) then return end
		local ok, exists = pcall(fn_isfile, path)
		if ok and exists then pcall(fn_delfile, path) end
	end
end

local RunCountPath = "NullUI/RunCount.txt"

local function BumpRunCount()
	local count = 1
	if fn_isfile and fn_readfile and fn_isfile(RunCountPath) then
		local ok, data = pcall(fn_readfile, RunCountPath)
		local n = ok and tonumber(data)
		if n then count = math.floor(n) + 1 end
	end
	if fn_writefile then
		EnsureAssetsFolder()
		pcall(fn_writefile, RunCountPath, tostring(count))
	end
	return count
end

local function GetExecutorName()
	local ok, name, version = pcall(function()
		if identifyexecutor then return identifyexecutor() end
		if getexecutorname then return getexecutorname() end
		if syn and syn.get_executor_name then return syn.get_executor_name() end
		return nil
	end)
	if ok and name and name ~= "" then
		return version and version ~= "" and (tostring(name) .. " " .. tostring(version)) or tostring(name)
	end
	return "Unknown"
end

local function FormatClock(minutesAfterMidnight)
	minutesAfterMidnight = minutesAfterMidnight or 0
	local h = math.floor(minutesAfterMidnight / 60) % 24
	local m = math.floor(minutesAfterMidnight % 60)
	local suffix = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%02d:%02d %s", h12, m, suffix)
end

local function LooksLikeFontFile(data)
	if type(data) ~= "string" or #data < 4096 then return false end
	local sig = data:sub(1, 4)
	return sig == "\0\1\0\0"
		or sig == "OTTO"
		or sig == "true"
		or sig == "ttcf"
		or sig == "wOFF"
		or sig == "wOF2"
end

local function DownloadFontFile(path, url)
	if not (fn_isfile and fn_writefile) then return false end

	local cached = nil
	if fn_isfile(path) and fn_readfile then
		local ok, data = pcall(fn_readfile, path)
		if ok and LooksLikeFontFile(data) then
			return true
		end
		cached = ok and data or nil
	end

	if cached ~= nil and fn_delfile then
		pcall(fn_delfile, path)
	end

	local ok, body = pcall(function() return game:HttpGet(url) end)
	if not ok or not LooksLikeFontFile(body) then
		return false
	end

	local wrote = pcall(fn_writefile, path, body)
	return wrote
end

local function LoadCustomFigtree()
	if not (fn_customasset and fn_writefile) then return nil end

	local okFolder = EnsureAssetsFolder()
	if not okFolder then return nil end

	local base = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/fonts/"
	local semiPath = ASSETS_FOLDER .. "/Figtree-SemiBold.ttf"
	local regPath  = ASSETS_FOLDER .. "/Figtree-Medium.ttf"

	if not DownloadFontFile(semiPath, base .. "Figtree-SemiBold.ttf") then
		return nil
	end
	local hasRegular = DownloadFontFile(regPath, base .. "Figtree-Medium.ttf")
	if not hasRegular then regPath = semiPath end

	local result = nil
	pcall(function()
		local family = {
			name = "Figtree",
			faces = {
				{ name = "Regular",  weight = 400, style = "normal", assetId = fn_customasset(regPath) },
				{ name = "SemiBold", weight = 600, style = "normal", assetId = fn_customasset(semiPath) },
			},
		}
		local familyPath = ASSETS_FOLDER .. "/Figtree.font"
		fn_writefile(familyPath, HttpService:JSONEncode(family))

		local asset = fn_customasset(familyPath)
		result = {
			Regular  = Font.new(asset, Enum.FontWeight.Regular,  Enum.FontStyle.Normal),
			SemiBold = Font.new(asset, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		}
	end)

	return result
end

local function LoadFonts()
	local custom = LoadCustomFigtree()
	if custom and custom.Regular and custom.SemiBold then
		return custom
	end

	local ok, native = pcall(function()
		return {
			Regular  = Font.new("rbxasset://fonts/families/Figtree.json", Enum.FontWeight.Regular,  Enum.FontStyle.Normal),
			SemiBold = Font.new("rbxasset://fonts/families/Figtree.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		}
	end)
	if ok and native then return native end

	return {
		Regular  = Font.fromEnum(Enum.Font.Gotham),
		SemiBold = Font.fromEnum(Enum.Font.GothamSemibold),
	}
end

local Fonts = LoadFonts()

NullUI.Theme = {
	Background     = Color3.fromRGB(16, 16, 16),
	Surface        = Color3.fromRGB(24, 24, 24),
	Text           = Color3.fromRGB(240, 240, 240),
	TextDim        = Color3.fromRGB(150, 150, 155),
	Accent         = Color3.fromRGB(255, 255, 255),
	Danger         = Color3.fromRGB(205, 205, 210),

	Font           = Fonts.SemiBold,
	FontRegular    = Fonts.Regular,

	MeasureFont    = Enum.Font.GothamSemibold,

	CornerRadius   = 16,
	CornerRadiusSm = 8,
	Margin         = 14,
	AnimFast       = 0.15,
	AnimSlow       = 0.32,
}

local ThemeBindings = setmetatable({}, {__mode = "k"})
local ThemePresets = {
 Dark = {{16,16,16},{24,24,24},{240,240,240},{150,150,155},{255,255,255}},
 Light = {{235,237,241},{215,220,228},{24,28,36},{80,89,104},{45,99,210}},
 Midnight = {{13,18,32},{24,33,53},{232,239,255},{146,166,198},{111,159,255}},
 Forest = {{15,26,22},{26,43,35},{232,246,237},{150,179,162},{108,209,153}},
}
local ThemeTokens = {"Background", "Surface", "Text", "TextDim", "Accent"}
local function BindTheme(instance, property, token)
 local bindings = ThemeBindings[instance] or {}
 ThemeBindings[instance] = bindings
 bindings[property] = token
 instance[property] = NullUI.Theme[token]
end
function NullUI:SetTheme(value)
 local colors = value
 if type(value) == "string" then
  assert(ThemePresets[value], "Unknown theme: " .. value)
  colors = {}
  for i, token in ipairs(ThemeTokens) do colors[token] = Color3.fromRGB(table.unpack(ThemePresets[value][i])) end
  self._ThemeName = value
 else
  assert(type(value) == "table", "Theme must be a name or color table")
  self._ThemeName = "Custom"
 end
 for token, color in pairs(colors) do
  if typeof(self.Theme[token]) == "Color3" and typeof(color) == "Color3" then self.Theme[token] = color end
 end
 for instance, bindings in pairs(ThemeBindings) do
  if instance.Parent then
   for property, token in pairs(bindings) do instance[property] = self.Theme[token] end
  end
 end
 return self
end

local Z = {
	Glass    = 0,
	Window   = 1,
	Content  = 2,
	Backdrop = 390,
	Popup    = 400,
	PopupTop = 410,
	Toast    = 600,
	Modal    = 800,
	ModalTop = 810,
}

local function Tween(instance, props, duration, style, direction)
 local bindings = ThemeBindings[instance]
 if bindings then
  for property, value in pairs(props) do
   if bindings[property] and value ~= NullUI.Theme[bindings[property]] then
    for _, token in ipairs(ThemeTokens) do
     if value == NullUI.Theme[token] then bindings[property] = token; break end
    end
   end
  end
 end
	local t = TweenService:Create(
		instance,
		TweenInfo.new(
			math.max(duration or 0.25, 0),
			style or Enum.EasingStyle.Quint,
			direction or Enum.EasingDirection.Out
		),
		props
	)
	t:Play()
	return t
end

local function Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or NullUI.Theme.CornerRadius)
	c.Parent = parent
	return c
end

local function Stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.9
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function GlassLayer(parent, radius, transparency)
	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.Size = UDim2.fromScale(1, 1)
	glass.BackgroundColor3 = Color3.new(1, 1, 1)
	glass.BackgroundTransparency = transparency or 0.985
	glass.BorderSizePixel = 0
	glass.ZIndex = Z.Glass
	glass.Parent = parent
	Corner(glass, radius)
	return glass
end

local function ObserveProperties(targets, callback)
	local owner = Janitor.new()
	local function schedule()
		if owner._dead then return end
		ScheduleUI(owner, function() if not owner._dead then callback() end end)
	end
	for _, target in ipairs(targets) do
		for i = 2, #target do owner:Add(target[1]:GetPropertyChangedSignal(target[i]):Connect(schedule)) end
	end
	owner:Add(function() UIJobs[owner] = nil end)
	owner.Disconnect = owner.Destroy
	schedule()
	return owner
end

local function BindWidthLayout(gui, callback)
	local previousWidth = nil
	local targets = {{gui, "AbsoluteSize", "Visible"}}
	local current = gui.Parent
	while current and current:IsA("GuiObject") do
		table.insert(targets, {current, "Visible"})
		current = current.Parent
	end
	local owner = ObserveProperties(targets, function()
		if not gui.Parent then return end
		local ancestor = gui
		while ancestor and ancestor:IsA("GuiObject") do
			if not ancestor.Visible then return end
			ancestor = ancestor.Parent
		end
		local width = gui.AbsoluteSize.X
		if width <= 0 or width == previousWidth then return end
		previousWidth = width
		callback()
	end)
	owner:Add(gui.Destroying:Connect(function() owner:Destroy() end))
	LibJanitor:Add(owner)
	return owner
end

local function AddScrollbar(scroll)
	scroll.ScrollBarThickness = 0
	scroll.ScrollBarImageTransparency = 1
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scroll.HorizontalScrollBarInset = Enum.ScrollBarInset.None
end

local function AddContentScrollThumb(scroll, listLayout, thumbParent, janitor, rightInset, thickness)
	local thumb = Instance.new("Frame")
	thumb.Name = "ContentScrollThumb"
	BindTheme(thumb, "BackgroundColor3", "TextDim")
	thumb.BackgroundTransparency = 0.35
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(1, 0)
	thumb.Size = UDim2.new(0, 3, 0, 40)
	thumb.Visible = false
	thumb.ZIndex = (scroll.ZIndex or 0) + 6
	thumb.Parent = thumbParent
	Corner(thumb, 2)

	local MARGIN = 4

	janitor:Add(ObserveProperties({
		{scroll, "AbsoluteWindowSize", "AbsoluteCanvasSize", "CanvasPosition", "AbsolutePosition", "AbsoluteSize", "Visible"},
		{thumbParent, "AbsolutePosition", "AbsoluteSize", "Visible"},
	}, function()
		if not thumbParent.Visible then
			thumb.Visible = false
			return
		end
		local windowH = scroll.AbsoluteWindowSize.Y
		local canvasH = scroll.AbsoluteCanvasSize.Y
		local overflow = canvasH - windowH
		if overflow <= 8 or windowH <= 0 then
			thumb.Visible = false
			return
		end
		local trackH = windowH - MARGIN * 2
		if trackH <= 0 then
			thumb.Visible = false
			return
		end
		local parentPos, parentSize = thumbParent.AbsolutePosition, thumbParent.AbsoluteSize
		if parentSize.X <= 0 or parentSize.Y <= 0 then
			thumb.Visible = false
			return
		end
		local thumbH = math.min(trackH, math.max(30, trackH * (windowH / canvasH)))
		local maxThumbY = trackH - thumbH
		local ratio = math.clamp(scroll.CanvasPosition.Y / overflow, 0, 1)
		local topY = (scroll.AbsolutePosition.Y - parentPos.Y) + MARGIN + maxThumbY * ratio
		local rightX = (scroll.AbsolutePosition.X + scroll.AbsoluteSize.X) - parentPos.X - (rightInset or MARGIN)
		thumb.Visible = true
		thumb.Size = UDim2.new(0, thickness or 3, thumbH / parentSize.Y, 0)
		thumb.Position = UDim2.new(rightX / parentSize.X, 0, topY / parentSize.Y, 0)
	end))

	return thumb
end

local MEASURE_FUDGE = 1.06
local MeasureCache = {}

local function MeasureText(text, size, maxWidth)
	text = tostring(text or "")
	maxWidth = maxWidth or 10000
	local key = text .. "\1" .. size .. "\1" .. math.floor(maxWidth)
	local cached = MeasureCache[key]
	if cached then return cached.X, cached.Y end

	local ok, bounds = pcall(function()
		return TextService:GetTextSize(
			text, size, NullUI.Theme.MeasureFont,
			Vector2.new(maxWidth, 100000)
		)
	end)
	local w, h
	if ok and bounds then
		w = math.ceil(bounds.X * MEASURE_FUDGE)
		h = math.ceil(bounds.Y)
	else
		w = math.ceil(#text * size * 0.55)
		h = size + 2
	end
	MeasureCache[key] = Vector2.new(w, h)
	return w, h
end

local IconSources = {
	Material = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/MaterialIcons.luau",
	Lucide   = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/LucideIcons.luau",
	Phosphor = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/Phosphor.luau",
	["Phosphor-Filled"] = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/Phosphor%20Filled.luau",
	SF       = "https://raw.githubusercontent.com/Skinny-yz/NullUI-Assets/main/icons/SFSymbols.luau",
}

local IconCache = {}
local IconLoading = {}

local function LoadIconSource(source)
	if IconCache[source] ~= nil then
		return IconCache[source] or nil
	end

	if IconLoading[source] then
		local t0 = os.clock()
		while IconLoading[source] and os.clock() - t0 < 10 do
			task.wait()
		end
		return IconCache[source] or nil
	end

	local url = IconSources[source]
	if not url then
		IconCache[source] = false
		return nil
	end

	IconLoading[source] = true
	local ok, data = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	IconLoading[source] = nil

	if ok and type(data) == "table" then
		IconCache[source] = data
		return data
	end

	IconCache[source] = false
	return nil
end

function NullUI:GetIcon(name, source)
	source = source or "Lucide"
	local set = LoadIconSource(source)
	local iconId = set and set[name]
	if not iconId then return "" end
	return "rbxassetid://" .. tostring(iconId)
end

local function ResolveIcon(icon)
	if icon == nil or icon == "" then return "" end
	if type(icon) ~= "string" then return icon end
	if icon:match("^%a[%w%+%-%.]*://") then return icon end
	if icon:match("^%d+$") then return "rbxassetid://" .. icon end
	local source, name = icon:match("^(%a[%w%-]*):(.+)$")
	if source and name then
		return NullUI:GetIcon(name, source)
	end
	return NullUI:GetIcon(icon, "Lucide")
end

function NullUI:PreloadIcons(sources)
	for _, src in ipairs(sources or { "Lucide" }) do
		task.spawn(LoadIconSource, src)
	end
end

local function GetRoot()
	local parent = PlayerGui
	local hidden = hasFn("gethui")
	if hidden then
		local ok, container = pcall(hidden)
		if ok and container then parent = container end
	end

	local stale = parent:FindFirstChild("NullUI")
	if stale then stale:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NullUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 9999
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = parent
	return screenGui
end

NullUI._Root = GetRoot()

local function ViewportSize()
	local root = NullUI._Root
	if root and root.AbsoluteSize.X > 0 then
		return root.AbsoluteSize
	end
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local UI_SCALE_BASELINE = IsMobileDevice and 380 or 720
local UI_SCALE_MIN = IsMobileDevice and 1.0 or 0.75
local UI_SCALE_MAX = IsMobileDevice and 1.5 or 1.35

local function ComputeUIScale()
	local view = ViewportSize()
	if IsMobileDevice then
		local width = NullUI._MobileDesignWidth or 605
		local height = NullUI._MobileDesignHeight or 405
		local reference = math.max(NullUI._MobileReferenceHeight or 450, height + 24)
		return math.max(0.05, math.min(view.Y / reference, math.max(1, view.X - 32) / width, math.max(1, view.Y - 24) / height))
	end
	return SafeClamp(view.Y / UI_SCALE_BASELINE, UI_SCALE_MIN, UI_SCALE_MAX)
end

local GlobalScale = Instance.new("UIScale")
GlobalScale.Name = "GlobalScale"
GlobalScale.Scale = ComputeUIScale() * (NullUI._DensityFactor or 1)
GlobalScale.Parent = NullUI._Root

local function GetUIScale()
	return GlobalScale.Scale
end

function NullUI:SetDensity(mode)
	assert(mode == "comfortable" or mode == "compact", "Density must be comfortable or compact")
	self._Density = mode
	self._DensityFactor = mode == "compact" and 0.85 or 1
	GlobalScale.Scale = ComputeUIScale() * self._DensityFactor
	if fn_writefile then
		pcall(function() EnsureAssetsFolder(); fn_writefile(ASSETS_FOLDER .. "/density.txt", mode) end)
	end
	return self
end
function NullUI:GetDensity() return self._Density or "comfortable" end
do
	if fn_readfile then
		local ok, mode = pcall(fn_readfile, ASSETS_FOLDER .. "/density.txt")
		if ok and (mode == "compact" or mode == "comfortable") then NullUI:SetDensity(mode) end
	end
end

local function RefreshUIScale()
	GlobalScale.Scale = ComputeUIScale() * (NullUI._DensityFactor or 1)
end

local function WatchCamera(cam)
	if not cam then return end
	LibJanitor:Add(cam:GetPropertyChangedSignal("ViewportSize"):Connect(RefreshUIScale))
end

WatchCamera(workspace.CurrentCamera)
LibJanitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	WatchCamera(workspace.CurrentCamera)
	RefreshUIScale()
end))

function NullUI:SetMobileScaleReference(height)
	self._MobileReferenceHeight = math.clamp(tonumber(height) or 450, 300, 2000)
	RefreshUIScale()
	return self
end

function NullUI:SetScaleRange(minScale, maxScale)
	UI_SCALE_MIN = minScale or UI_SCALE_MIN
	UI_SCALE_MAX = maxScale or UI_SCALE_MAX
	RefreshUIScale()
end

local ActivePopupClose = nil

local function RegisterPopupOpen(closeFn)
	if ActivePopupClose and ActivePopupClose ~= closeFn then
		local previous = ActivePopupClose
		ActivePopupClose = nil
		previous()
	end
	ActivePopupClose = closeFn
end

local function RegisterPopupClose(closeFn)
	if ActivePopupClose == closeFn then
		ActivePopupClose = nil
	end
end

local function CloseAnyOpenPopup()
	if ActivePopupClose then
		local fn = ActivePopupClose
		ActivePopupClose = nil
		fn()
	end
end

local function MakePopupBackdrop(onClose)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "PopupBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Backdrop
	backdrop.Parent = NullUI._Root
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			onClose()
		end
	end)
	return backdrop
end

LibJanitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and ActivePopupClose then
		CloseAnyOpenPopup()
	end
end))

local KeybindCapturing = false

local NotificationQueue = {}
local NotificationHistory = {}
function NullUI:GetNotificationHistory()
	local result = {}
	for i, item in ipairs(NotificationHistory) do result[i] = table.clone(item) end
	return result
end
function NullUI:ClearNotificationHistory() table.clear(NotificationHistory) end

local function GetNotifyHolder()
	local root = NullUI._Root
	local holder = root:FindFirstChild("NotificationHolder")
	if holder then return holder end

	holder = Instance.new("Frame")
	holder.Name = "NotificationHolder"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -20, 1, -20)
	holder.Size = UDim2.new(0, 280, 1, -40)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z.Toast
	holder.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 10)
	layout.Parent = holder
	holder.ClipsDescendants = true

	LibJanitor:Add(RunService.Heartbeat:Connect(function()
		if not holder.Parent then return end
		local s = GetUIScale()
		local view = ViewportSize()
		holder.Size = UDim2.fromOffset(math.max(1, math.min(280, view.X / s - 40)), math.max(1, view.Y / s - 40))
		local used, count = 0, 0
		local function fullHeight(card)
			local anim = card:FindFirstChildOfClass("UIScale")
			return card.AbsoluteSize.Y / (anim and math.max(anim.Scale, 0.01) or 1)
		end
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				used += fullHeight(child) + (count > 0 and 10 * s or 0)
				count += 1
			end
		end
		while #NotificationQueue > 0 do
			local entry = NotificationQueue[1]
			if not entry.Card.Parent then
				table.remove(NotificationQueue, 1)
			else
				local h = fullHeight(entry.Card)
				if h <= 0 then break end
				local needed = h + (count > 0 and 10 * s or 0)
				if used + needed > holder.AbsoluteSize.Y then break end
				table.remove(NotificationQueue, 1)
				entry.Start()
				used += needed
				count += 1
			end
		end
	end))

	return holder
end

NullUI._NotifyCounter = 0

local NotifyIcons = {
	info    = "info",
	success = "check",
	warning = "triangle-alert",
	error   = "circle-x",
}

local NotifyColors = {
	info    = Color3.fromRGB(120, 170, 255),
	success = Color3.fromRGB(110, 220, 140),
	warning = Color3.fromRGB(255, 190, 90),
	error   = Color3.fromRGB(255, 105, 105),
}

function NullUI:Notify(opts)
	opts = opts or {}
	local title      = opts.Title or "Notification"
	local text       = opts.Text or ""
	local duration   = opts.Duration or 4
	local notifyType = opts.Type or "info"
	local color      = opts.Color or NotifyColors[notifyType] or NullUI.Theme.Accent
	local iconName   = opts.Icon or NotifyIcons[notifyType] or NotifyIcons.info

	local holder = GetNotifyHolder()
	NullUI._NotifyCounter = NullUI._NotifyCounter + 1

	local dismiss

	local card = Instance.new("Frame")
	card.Name = "Notification"
	BindTheme(card, "BackgroundColor3", "Surface")
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.LayoutOrder = NullUI._NotifyCounter
	card.ZIndex = Z.Toast
	card.Visible = false
	card.Parent = holder
	Corner(card, 12)
	local stroke = Stroke(card, Color3.new(1, 1, 1), 1, 1)
	local notificationAcrylic = nil
	local scale = Instance.new("UIScale")
	scale.Scale = 0.88
	scale.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local headerRow = Instance.new("Frame")
	headerRow.BackgroundTransparency = 1
	headerRow.AutomaticSize = Enum.AutomaticSize.XY
	headerRow.Size = UDim2.new(0, 0, 0, 0)
	headerRow.LayoutOrder = 1
	headerRow.ZIndex = Z.Toast + 1
	headerRow.Parent = card

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.Padding = UDim.new(0, 7)
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = headerRow

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ResolveIcon(iconName)
	icon.ImageColor3 = color
	icon.ImageTransparency = 1
	icon.Size = UDim2.fromOffset(14, 14)
	icon.LayoutOrder = 1
	icon.ZIndex = Z.Toast + 1
	icon.Parent = headerRow

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.XY
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Toast + 1
	titleLabel.Parent = headerRow

	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = NullUI.Theme.FontRegular
		textLabel.Text = text
		BindTheme(textLabel, "TextColor3", "TextDim")
		textLabel.TextTransparency = 1
		textLabel.TextSize = 12
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.LayoutOrder = 2
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.ZIndex = Z.Toast + 1
		textLabel.Parent = card
	end

	local actionButtons = {}
	if type(opts.Actions) == "table" and #opts.Actions > 0 then
		local actionsRow = Instance.new("Frame")
		actionsRow.Name = "Actions"
		actionsRow.BackgroundTransparency = 1
		actionsRow.AutomaticSize = Enum.AutomaticSize.Y
		actionsRow.Size = UDim2.new(1, 0, 0, 0)
		actionsRow.LayoutOrder = 3
		actionsRow.ZIndex = Z.Toast + 1
		actionsRow.Parent = card

		local actionsLayout = Instance.new("UIListLayout")
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.Padding = UDim.new(0, 6)
		actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionsLayout.Parent = actionsRow

		for i, action in ipairs(opts.Actions) do
			local btn = Instance.new("TextButton")
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = color
			btn.BackgroundTransparency = 1
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.Size = UDim2.fromOffset(0, 22)
			btn.LayoutOrder = i
			btn.ZIndex = Z.Toast + 1
			btn.Parent = actionsRow
			Corner(btn, 6)
			local btnStroke = Stroke(btn, color, 1, 1)

			local btnPad = Instance.new("UIPadding")
			btnPad.PaddingLeft = UDim.new(0, 8)
			btnPad.PaddingRight = UDim.new(0, 8)
			btnPad.Parent = btn

			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = NullUI.Theme.Font
			lbl.Text = action.Text or "Action"
			lbl.TextColor3 = color
			lbl.TextTransparency = 1
			lbl.TextSize = 12
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.fromOffset(0, 22)
			lbl.ZIndex = Z.Toast + 2
			lbl.Parent = btn

			Tween(btn, { BackgroundTransparency = 0.85 }, 0.28)
			Tween(btnStroke, { Transparency = 0.6 }, 0.28)
			Tween(lbl, { TextTransparency = 0 }, 0.28)

			btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0.7 }, 0.12) end)
			btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = 0.85 }, 0.12) end)
			btn.MouseButton1Click:Connect(function()
				if action.Callback then task.spawn(action.Callback) end
				if action.DismissOnClick ~= false then dismiss() end
			end)

			table.insert(actionButtons, { Button = btn, Stroke = btnStroke, Label = lbl })
		end
	end

	local barHolder = Instance.new("Frame")
	barHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	barHolder.BackgroundTransparency = 1
	barHolder.BorderSizePixel = 0
	barHolder.Size = UDim2.new(1, 0, 0, 3)
	barHolder.LayoutOrder = 4
	barHolder.ZIndex = Z.Toast + 1
	barHolder.Parent = card
	Corner(barHolder, 2)

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = color
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 0, 0.5, 0)
	bar.Size = UDim2.fromScale(1, 1)
	bar.ZIndex = Z.Toast + 2
	bar.Parent = barHolder
	Corner(bar, 2)

	local barGradient = Instance.new("UIGradient")
	barGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.4)),
		ColorSequenceKeypoint.new(1, color),
	})
	barGradient.Parent = bar


	local dismissed = false
	function dismiss()
		if dismissed or not card.Parent then return end
		dismissed = true
		if not card.Visible then card:Destroy(); return end

		local currentHeight = card.AbsoluteSize.Y / GetUIScale()
		card.AutomaticSize = Enum.AutomaticSize.None
		card.Size = UDim2.new(1, 0, 0, currentHeight)

		Tween(card, { BackgroundTransparency = 1 }, 0.16)
		Tween(stroke, { Transparency = 1 }, 0.16)
		Tween(scale, { Scale = 0.9 }, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(icon, { ImageTransparency = 1 }, 0.16)
		Tween(titleLabel, { TextTransparency = 1 }, 0.16)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.16) end

		task.delay(0.1, function()
			if card and card.Parent then
				Tween(card, { Size = UDim2.new(1, 0, 0, 0) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			end
		end)

		task.delay(0.34, function()
			if notificationAcrylic then
				notificationAcrylic:Destroy()
				notificationAcrylic = nil
			end
			if card then card:Destroy() end
		end)
	end

	local function startNotification()
		if dismissed or not card.Parent then return end
		table.insert(NotificationHistory, { Title = tostring(title), Text = tostring(text), Type = notifyType, Time = os.time() })
		if #NotificationHistory > 100 then table.remove(NotificationHistory, 1) end
		card.Visible = true
		notificationAcrylic = CreateWindowAcrylic(card)
	Tween(card, { BackgroundTransparency = 0.25 }, 0.28)
	Tween(stroke, { Transparency = 0.82 }, 0.28)
	Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Tween(icon, { ImageTransparency = 0 }, 0.28)
	Tween(titleLabel, { TextTransparency = 0 }, 0.28)
	Tween(barHolder, { BackgroundTransparency = 0.88 }, 0.28)
	Tween(bar, { BackgroundTransparency = 0 }, 0.28)
	if textLabel then
		Tween(textLabel, { TextTransparency = 0 }, 0.28)
	end

	task.delay(0.05, function()
		if bar and bar.Parent then
			Tween(bar, { Size = UDim2.new(0, 0, 1, 0) }, duration - 0.05,
				Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		end
	end)

		task.delay(duration, dismiss)
	end
	table.insert(NotificationQueue, { Card = card, Start = startNotification })

	return {
		Instance = card,
		Dismiss = dismiss,
	}
end

local function ComputeDialogCenter(anchorFrame)
	local view = ViewportSize()
	if not anchorFrame or anchorFrame.AbsoluteSize.X <= 0 then
		return view.X / 2, view.Y / 2
	end
	local pos, size = anchorFrame.AbsolutePosition, anchorFrame.AbsoluteSize
	local cx = SafeClamp(pos.X + size.X / 2, 190, math.max(190, view.X - 190))
	local cy = SafeClamp(pos.Y + size.Y / 2, 110, math.max(110, view.Y - 110))
	return cx, cy
end

function NullUI:Confirm(opts)
	opts = opts or {}
	local title       = opts.Title or "Confirm"
	local text        = opts.Text or ""
	local confirmText = opts.ConfirmText or "Confirm"
	local cancelText  = opts.CancelText or "Cancel"
	local danger      = opts.Danger == true
	local anchorFrame = opts.Window
	if type(anchorFrame) == "table" then
		anchorFrame = anchorFrame._gui
	end

	local root = NullUI._Root
	local jan = Janitor.new()

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ConfirmBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root

	local dialog = Instance.new("Frame")
	dialog.Name = "ConfirmDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(anchorFrame)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	BindTheme(dialog, "BackgroundColor3", "Surface")
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 340, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	Corner(dialog, 16)
	local dialogStroke = Stroke(dialog, Color3.new(1, 1, 1), 1, 1)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = dialog

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = dialog

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dialog

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = danger and NullUI.Theme.Danger or NullUI.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = Z.ModalTop + 1
	titleLabel.Parent = dialog

	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = NullUI.Theme.FontRegular
		textLabel.Text = text
		BindTheme(textLabel, "TextColor3", "TextDim")
		textLabel.TextTransparency = 1
		textLabel.TextSize = 14
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.LineHeight = 1.25
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.LayoutOrder = 2
		textLabel.ZIndex = Z.ModalTop + 1
		textLabel.Parent = dialog
	end

	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.LayoutOrder = 3
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingTop = UDim.new(0, 6)
	rowPad.Parent = buttonsRow

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow

	local function makeButton(text_, order, filled)
		local tint = (filled and danger) and NullUI.Theme.Danger or Color3.new(1, 1, 1)

		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = tint
		btn.BackgroundTransparency = filled and (danger and 0.55 or 0.82) or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, tint, 1, filled and 0.7 or 0.85)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = NullUI.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = (filled and danger) and NullUI.Theme.Danger or NullUI.Theme.Text
		lbl.TextSize = 14
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn

		local baseBg = btn.BackgroundTransparency
		local baseStroke = btnStroke.Transparency

		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max(baseBg - 0.1, 0) }, 0.12)
			Tween(btnStroke, { Transparency = math.max(baseStroke - 0.15, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = baseBg }, 0.12)
			Tween(btnStroke, { Transparency = baseStroke }, 0.12)
		end))

		return btn
	end

	local cancelBtn  = makeButton(cancelText, 1, false)
	local confirmBtn = makeButton(confirmText, 2, true)

	local closed = false
	local function close(confirmed)
		if closed then return end
		closed = true

		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		Tween(titleLabel, { TextTransparency = 1 }, 0.12)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.12) end

		task.delay(0.18, function()
			jan:Destroy()
			if backdrop then backdrop:Destroy() end
		end)

		if opts.Callback then task.spawn(opts.Callback, confirmed) end
	end

	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(confirmBtn.MouseButton1Click:Connect(function() close(true) end))

	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			close(true)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			close(false)
		end
	end))

	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(titleLabel, { TextTransparency = 0 }, 0.2)
	if textLabel then Tween(textLabel, { TextTransparency = 0 }, 0.2) end
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	return { Close = close }
end

function NullUI:Modal(opts)
	opts = opts or {}
	local title       = opts.Title or "Modal"
	local text        = opts.Text or ""
	local confirmText = opts.ConfirmText or "Confirm"
	local cancelText  = opts.CancelText or "Cancel"
	local danger      = opts.Danger == true
	local fields      = opts.Fields or {}
	local anchorFrame = opts.Window
	if type(anchorFrame) == "table" then
		anchorFrame = anchorFrame._gui
	end

	local root = NullUI._Root
	local jan = Janitor.new()

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root

	local dialog = Instance.new("Frame")
	dialog.Name = "ModalDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(anchorFrame)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	BindTheme(dialog, "BackgroundColor3", "Surface")
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 360, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	Corner(dialog, 16)
	local dialogStroke = Stroke(dialog, Color3.new(1, 1, 1), 1, 1)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = dialog

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = dialog

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dialog

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = danger and NullUI.Theme.Danger or NullUI.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = Z.ModalTop + 1
	titleLabel.Parent = dialog

	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = NullUI.Theme.FontRegular
		textLabel.Text = text
		BindTheme(textLabel, "TextColor3", "TextDim")
		textLabel.TextTransparency = 1
		textLabel.TextSize = 13
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.LineHeight = 1.25
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.LayoutOrder = 2
		textLabel.ZIndex = Z.ModalTop + 1
		textLabel.Parent = dialog
	end

	local fieldsHolder = Instance.new("Frame")
	fieldsHolder.BackgroundTransparency = 1
	fieldsHolder.AutomaticSize = Enum.AutomaticSize.Y
	fieldsHolder.Size = UDim2.new(1, 0, 0, 0)
	fieldsHolder.LayoutOrder = 3
	fieldsHolder.ZIndex = Z.ModalTop + 1
	fieldsHolder.Parent = dialog

	local fieldsLayout = Instance.new("UIListLayout")
	fieldsLayout.Padding = UDim.new(0, 10)
	fieldsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fieldsLayout.Parent = fieldsHolder

	local fieldBoxes = {}

	for i, field in ipairs(fields) do
		local isTextarea = field.Type == "textarea"
		local labelH = field.Label and field.Label ~= "" and 16 or 0
		local boxH = isTextarea and 60 or 34

		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.LayoutOrder = i
		holder.ZIndex = Z.ModalTop + 1
		holder.Parent = fieldsHolder

		local holderLayout = Instance.new("UIListLayout")
		holderLayout.Padding = UDim.new(0, 4)
		holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
		holderLayout.Parent = holder

		if labelH > 0 then
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = NullUI.Theme.FontRegular
			lbl.Text = string.upper(field.Label)
			lbl.TextColor3 = danger and NullUI.Theme.Danger or NullUI.Theme.TextDim
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Size = UDim2.new(1, 0, 0, labelH)
			lbl.LayoutOrder = 1
			lbl.ZIndex = Z.ModalTop + 2
			lbl.Parent = holder
		end

		local fieldFrame = Instance.new("Frame")
		fieldFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		fieldFrame.BackgroundTransparency = 0.93
		fieldFrame.BorderSizePixel = 0
		fieldFrame.Size = UDim2.new(1, 0, 0, boxH)
		fieldFrame.LayoutOrder = 2
		fieldFrame.ZIndex = Z.ModalTop + 2
		fieldFrame.Parent = holder
		Corner(fieldFrame, 9)
		local fieldStroke = Stroke(fieldFrame, Color3.new(1, 1, 1), 1, 0.88)

		local fieldPad = Instance.new("UIPadding")
		fieldPad.PaddingLeft = UDim.new(0, 10)
		fieldPad.PaddingRight = UDim.new(0, 10)
		fieldPad.PaddingTop = UDim.new(0, isTextarea and 8 or 0)
		fieldPad.Parent = fieldFrame

		local box = Instance.new("TextBox")
		box.ClearTextOnFocus = false
		box.MultiLine = isTextarea
		box.FontFace = NullUI.Theme.FontRegular
		box.PlaceholderText = field.Placeholder or ""
		box.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
		box.Text = tostring(field.Default or "")
		BindTheme(box, "TextColor3", "Text")
		box.TextSize = 13
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = isTextarea and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
		box.TextWrapped = isTextarea
		box.ClipsDescendants = true
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = Z.ModalTop + 3
		box.Parent = fieldFrame

		if field.MaxLength then
			jan:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
				if utf8.len(box.Text) and utf8.len(box.Text) > field.MaxLength then
					box.Text = string.sub(box.Text, 1, field.MaxLength)
				end
			end))
		end

		jan:Add(box.Focused:Connect(function()
			Tween(fieldStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
			Tween(fieldFrame, { BackgroundTransparency = 0.85 }, 0.15)
		end))
		jan:Add(box.FocusLost:Connect(function()
			Tween(fieldStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
			Tween(fieldFrame, { BackgroundTransparency = 0.93 }, 0.15)
		end))

		fieldBoxes[field.Key or i] = { Type = field.Type, Box = box }
	end

	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.LayoutOrder = 4
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingTop = UDim.new(0, 4)
	rowPad.Parent = buttonsRow

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow

	local function makeButton(text_, order, filled)
		local tint = (filled and danger) and NullUI.Theme.Danger or Color3.new(1, 1, 1)

		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = tint
		btn.BackgroundTransparency = filled and (danger and 0.55 or 0.82) or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, tint, 1, filled and 0.7 or 0.85)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = NullUI.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = (filled and danger) and NullUI.Theme.Danger or NullUI.Theme.Text
		lbl.TextSize = 14
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn

		local baseBg = btn.BackgroundTransparency
		local baseStroke = btnStroke.Transparency

		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max(baseBg - 0.1, 0) }, 0.12)
			Tween(btnStroke, { Transparency = math.max(baseStroke - 0.15, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = baseBg }, 0.12)
			Tween(btnStroke, { Transparency = baseStroke }, 0.12)
		end))

		return btn
	end

	local cancelBtn  = makeButton(cancelText, 1, false)
	local confirmBtn = makeButton(confirmText, 2, true)

	local function collectValues()
		local values = {}
		for key, entry in pairs(fieldBoxes) do
			if entry.Type == "tags" then
				local list = {}
				for piece in string.gmatch(entry.Box.Text, "[^,]+") do
					local trimmed = piece:gsub("^%s+", ""):gsub("%s+$", "")
					if trimmed ~= "" then table.insert(list, trimmed) end
				end
				values[key] = list
			else
				values[key] = entry.Box.Text
			end
		end
		return values
	end

	local closed = false
	local function close(confirmed)
		if closed then return end
		closed = true

		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		Tween(titleLabel, { TextTransparency = 1 }, 0.12)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.12) end

		task.delay(0.18, function()
			jan:Destroy()
			if backdrop then backdrop:Destroy() end
		end)

		if opts.Callback then
			task.spawn(opts.Callback, confirmed, confirmed and collectValues() or nil)
		end
	end

	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(confirmBtn.MouseButton1Click:Connect(function() close(true) end))

	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			close(false)
		end
	end))

	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(titleLabel, { TextTransparency = 0 }, 0.2)
	if textLabel then Tween(textLabel, { TextTransparency = 0 }, 0.2) end
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	return { Close = close }
end

local DRAG_SMOOTH_SPEED = 22

local function SetupSmoothDrag(frame, handle, janitor)
	handle = handle or frame

	local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
	if detector then detector.Enabled = false end

	local dragging = false
	local settling = false
	local mouseOffset = Vector2.zero
	local activeInput = nil

	local function frameOffset()
		local pos = frame.Position
		local parentSize = ViewportSize()
		if frame.Parent and frame.Parent:IsA("GuiObject") and frame.Parent.AbsoluteSize.X > 0 then
			parentSize = frame.Parent.AbsoluteSize
		end
		local s = GetUIScale()
		return Vector2.new(
			pos.X.Scale * parentSize.X + pos.X.Offset * s,
			pos.Y.Scale * parentSize.Y + pos.Y.Offset * s
		)
	end

	local currentPosition = frameOffset()
	local targetPosition = currentPosition

	local function clampToScreen(pos)
		local view = ViewportSize()
		local size = frame.AbsoluteSize
		local anchor = frame.AnchorPoint
		local minVisible = 60
		local left = pos.X - size.X * anchor.X
		local top  = pos.Y - size.Y * anchor.Y
		left = SafeClamp(left, -size.X + minVisible, view.X - minVisible)
		-- A ScreenGui vive abaixo do inset do topo, entao travar em 0 era o teto invisivel
		-- que impedia arrastar a janela pra cima. -inset.Y libera ate a borda real da tela.
		top  = SafeClamp(top, -GuiService:GetGuiInset().Y, view.Y - minVisible)
		return Vector2.new(left + size.X * anchor.X, top + size.Y * anchor.Y)
	end

	local api = {}

	function api.Sync()
		currentPosition = frameOffset()
		targetPosition = currentPosition
		settling = false
	end

	janitor:Add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging then return end
		dragging = true
		settling = true
		activeInput = input
		currentPosition = frameOffset()
		targetPosition = currentPosition
		mouseOffset = Vector2.new(input.Position.X, input.Position.Y) - currentPosition
	end))

	janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch
			and activeInput and input ~= activeInput then
			return
		end
		targetPosition = clampToScreen(
			Vector2.new(input.Position.X, input.Position.Y) - mouseOffset
		)
	end))

	janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if input == activeInput
			or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			activeInput = nil
		end
	end))

	janitor:Add(RunService.RenderStepped:Connect(function(dt)
		if not dragging and not settling then return end
		if not frame.Parent then return end

		local alpha = 1 - math.exp(-DRAG_SMOOTH_SPEED * dt)
		currentPosition = currentPosition:Lerp(targetPosition, alpha)

		if not dragging and (currentPosition - targetPosition).Magnitude < 0.5 then
			currentPosition = targetPosition
			settling = false
		end

		local s = GetUIScale()
  local nextPosition = UDim2.fromOffset(math.round(currentPosition.X / s), math.round(currentPosition.Y / s))
  if frame.Position ~= nextPosition then frame.Position = nextPosition end
	end))

	return api
end

local function SetupResize(frame, handle, janitor, opts)
	opts = opts or {}
	local minSize = opts.MinSize or Vector2.new(420, 300)
	local onResize = opts.OnResize

	local resizing = false
	local startSize, startTopLeft, startInput, activeInput

	janitor:Add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if resizing then return end
		resizing = true
		activeInput = input
		startSize = frame.AbsoluteSize
		startTopLeft = frame.AbsolutePosition
		startInput = Vector2.new(input.Position.X, input.Position.Y)
	end))

	local pendingPosition
	local resizeJob = {}
	local function applyResize()
		if not pendingPosition or not frame.Parent then return end
		local position = pendingPosition
		pendingPosition = nil
		local view = ViewportSize()
		local delta = Vector2.new(position.X, position.Y) - startInput
		local maxW = math.max(view.X - startTopLeft.X - 8, 100)
		local maxH = math.max(view.Y - startTopLeft.Y - 8, 100)
		local newW = SafeClamp(startSize.X + delta.X, math.min(minSize.X * GetUIScale(), maxW), maxW)
		local newH = SafeClamp(startSize.Y + delta.Y, math.min(minSize.Y * GetUIScale(), maxH), maxH)

		local s = GetUIScale()
		frame.Size = UDim2.fromOffset(math.round(newW / s), math.round(newH / s))

		local centerX = startTopLeft.X + newW / 2
		local centerY = startTopLeft.Y + newH / 2
		frame.Position = UDim2.fromOffset(math.round(centerX / s), math.round(centerY / s))

		if onResize then onResize(frame.Size, false) end
	end
	janitor:Add(function() UIJobs[resizeJob] = nil end)
	janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if not resizing then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if input.UserInputType == Enum.UserInputType.Touch and input ~= activeInput then return end
		pendingPosition = input.Position
		ScheduleUI(resizeJob, applyResize)
	end))

	janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if not resizing then return end
		if input == activeInput
			or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			applyResize()
			UIJobs[resizeJob] = nil
			resizing = false
			activeInput = nil
			if onResize then onResize(frame.Size, true) end
		end
	end))
end

local DRAG_THRESHOLD = 6

local function BaseCard(parent, height)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BackgroundTransparency = 0.96
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, height or 44)
	card.ZIndex = Z.Content
	card.Parent = parent
	Corner(card, NullUI.Theme.CornerRadiusSm)
	Stroke(card, Color3.new(1, 1, 1), 1, 0.95)
	return card
end

local function CreateInputPill(card, width)
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -14, 0.5, 0)
	pill.Size = UDim2.fromOffset(width, 26)
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.9
	pill.BorderSizePixel = 0
	pill.ZIndex = Z.Content + 2
	pill.Parent = card
	Corner(pill, 8)
	return pill, Stroke(pill, Color3.new(1, 1, 1), 1, 0.88)
end

local function AddLeadingIcon(card, icon, height)
	local asset = icon and ResolveIcon(icon) or ""
	if asset == "" then return 14, nil end

	local img = Instance.new("ImageLabel")
	img.Name = "LeadingIcon"
	img.BackgroundTransparency = 1
	img.Image = asset
	BindTheme(img, "ImageColor3", "TextDim")
	img.Size = UDim2.fromOffset(16, 16)
	img.AnchorPoint = Vector2.new(0, 0.5)
	img.Position = UDim2.new(0, 14, 0.5, 0)
	img.ZIndex = Z.Content + 1
	img.Parent = card
	return 14 + 16 + 10, img
end

local function AddTitleDesc(card, x, rightReserve, title, description, baseHeight, extraBottom)
	extraBottom = extraBottom or 0
	local hasDesc = description ~= nil and description ~= ""
	local titleH, descH, gap = 16, 14, 3

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, titleH)
	titleLabel.Position = UDim2.fromOffset(x, 0)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card

	local descLabel
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = NullUI.Theme.FontRegular
		descLabel.Text = description
		BindTheme(descLabel, "TextColor3", "TextDim")
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, descH)
		descLabel.Position = UDim2.fromOffset(x, titleH + gap)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end

	local lastWidth = -1
	local lastReserve = -1

	local function relayout()
		local cardW = card.AbsoluteSize.X / GetUIScale()
		if cardW <= 0 then return end
		local reserve = type(rightReserve) == "function" and rightReserve() or rightReserve
		if math.abs(cardW - lastWidth) < 1 and reserve == lastReserve then return end
		lastReserve = reserve
		titleLabel.Size = UDim2.new(1, -(x + reserve), 0, titleH)
		lastWidth = cardW

		local avail = math.max(cardW - x - reserve, 1)
		local realDescH = descH
		if hasDesc then
			local _, h = MeasureText(description, 12, avail)
			realDescH = math.max(descH, h)
			descLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, realDescH)
		end

		local blockH = hasDesc and (titleH + gap + realDescH) or titleH
		local topPortion = math.max(baseHeight, blockH + 18)
		card.Size = UDim2.new(1, 0, 0, topPortion + extraBottom)

		local top = math.floor((topPortion - blockH) / 2)
		titleLabel.Position = UDim2.fromOffset(x, top)
		if hasDesc then
			descLabel.Position = UDim2.fromOffset(x, top + titleH + gap)
		end
	end

	BindWidthLayout(card, relayout)
	task.defer(relayout)

	return titleLabel, descLabel, relayout
end

local function AddEmptyState(scroll, overlayParent, janitor)
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Size = UDim2.fromScale(1, 1)
	emptyState.ZIndex = (scroll.ZIndex or 0) + 5
	emptyState.Parent = overlayParent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = emptyState

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ResolveIcon("frown")
	BindTheme(icon, "ImageColor3", "TextDim")
	icon.Size = UDim2.fromOffset(26, 26)
	icon.LayoutOrder = 1
	icon.ZIndex = emptyState.ZIndex + 1
	icon.Parent = emptyState

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = NullUI.Theme.FontRegular
	label.Text = "There's nothing here yet"
	BindTheme(label, "TextColor3", "TextDim")
	label.TextSize = 13
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 16)
	label.LayoutOrder = 2
	label.ZIndex = emptyState.ZIndex + 1
	label.Parent = emptyState

	local function update()
		local hasContent = false
		for _, child in ipairs(scroll:GetChildren()) do
			local cn = child.ClassName
			if cn ~= "UIListLayout" and cn ~= "UIPadding" then
				hasContent = true
				break
			end
		end
		emptyState.Visible = not hasContent
	end

	janitor:Add(scroll.ChildAdded:Connect(update))
	janitor:Add(scroll.ChildRemoved:Connect(update))
	update()

	return emptyState
end

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

function NullUI:CreateWindow(opts)
	opts = opts or {}
	local size = opts.Size or UDim2.fromOffset(605, 405)

	if IsMobileDevice then
		local width = size.X.Offset > 0 and size.X.Offset or 605
		local height = size.Y.Offset > 0 and size.Y.Offset or 405
		NullUI._MobileDesignWidth = math.max(NullUI._MobileDesignWidth or 0, width)
		NullUI._MobileDesignHeight = math.max(NullUI._MobileDesignHeight or 0, height)
		RefreshUIScale()
		size = UDim2.fromOffset(width, height)
	end
	local margin = NullUI.Theme.Margin

	local root = NullUI._Root
	local jan = Janitor.new()

	local main = Instance.new("Frame")
	main.Name = "Window"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, IsMobileDevice and 0.5 or 0.55)
	main.Size = size
	main:SetAttribute("InitialSize", size)
	main:SetAttribute("InitialPosition", main.Position)
	BindTheme(main, "BackgroundColor3", "Background")
	main.BackgroundTransparency = 1
	main.BorderSizePixel = 0
	main.ClipsDescendants = true
	main.ZIndex = Z.Window
	main.Parent = root
	Corner(main, NullUI.Theme.CornerRadius)
	Stroke(main, Color3.new(1, 1, 1), 1, 0.92)
	GlassLayer(main, NullUI.Theme.CornerRadius, 0.985)

	local topbar = Instance.new("Frame")
	topbar.Name = "TopBar"
	topbar.BackgroundTransparency = 1
	topbar.Size = UDim2.new(1, 0, 0, 52)
	topbar.ZIndex = Z.Content
	topbar.Parent = main

	local controlsHolder = Instance.new("Frame")
	controlsHolder.Name = "WindowControls"
	controlsHolder.AnchorPoint = Vector2.new(1, 0.5)
	controlsHolder.Position = UDim2.new(1, -margin, 0.5, 0)
	controlsHolder.Size = UDim2.fromOffset(120, 26)
	controlsHolder.BackgroundTransparency = 1
	controlsHolder.ZIndex = Z.Content + 1
	controlsHolder.Parent = topbar

	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controlsHolder

	local function addControl(icon, name, order, hoverColor)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(26, 26)
		btn.LayoutOrder = order
		btn.ZIndex = Z.Content + 1
		btn.Parent = controlsHolder
		Corner(btn, 8)

		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		BindTheme(ic, "ImageColor3", "TextDim")
		ic.Size = UDim2.fromOffset(14, 14)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = Z.Content + 2
		ic.Parent = btn

		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = hoverColor or NullUI.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = NullUI.Theme.TextDim }, 0.12)
		end))
		return btn
	end

	local searchBtn = addControl("search",   "SearchButton",     1)
	local minBtn    = addControl("minus",    "MinimizeButton",   2)
	local fullBtn   = addControl("maximize", "FullscreenButton", 3)
	local closeBtn  = addControl("x",        "CloseButton",      4)

	local titleStartX  = margin + 5
	local titleTextPad = 146

	local hasIcon = opts.Icon and opts.Icon ~= ""
	if hasIcon then
		local windowIcon = Instance.new("ImageLabel")
		windowIcon.Name = "WindowIcon"
		windowIcon.BackgroundTransparency = 1
		windowIcon.Image = ResolveIcon(opts.Icon)
		BindTheme(windowIcon, "ImageColor3", "Text")
		windowIcon.Size = UDim2.fromOffset(20, 20)
		windowIcon.AnchorPoint = Vector2.new(0, 0.5)
		windowIcon.Position = UDim2.new(0, titleStartX, 0.5, 0)
		windowIcon.ZIndex = Z.Content
		windowIcon.Parent = topbar
		titleStartX += 20 + 8
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = opts.Title or "Window"
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(titleStartX, opts.Subtitle and 8 or 0)
	titleLabel.Size = UDim2.new(1, -titleStartX - titleTextPad, 0, 20)
	titleLabel.ZIndex = Z.Content
	titleLabel.Parent = topbar

	local subLabel
	if opts.Subtitle then
		subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.BackgroundTransparency = 1
		subLabel.FontFace = NullUI.Theme.FontRegular
		subLabel.Text = opts.Subtitle
		BindTheme(subLabel, "TextColor3", "TextDim")
		subLabel.TextSize = 13
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Center
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.Position = UDim2.fromOffset(titleStartX, 28)
		subLabel.Size = UDim2.new(1, -titleStartX - titleTextPad, 0, 14)
		subLabel.ZIndex = Z.Content
		subLabel.Parent = topbar
	end

	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Position = UDim2.fromOffset(margin, 58)
	tabBar.Size = UDim2.new(0, 130, 1, -(58 + margin))
	tabBar.ScrollBarThickness = 0
	tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabBar.ZIndex = Z.Content
	tabBar.Parent = main

	local tabBarLayout = Instance.new("UIListLayout")
	tabBarLayout.Padding = UDim.new(0, 4)
	tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabBarLayout.Parent = tabBar

	AddScrollbar(tabBar)
	if opts.TabScrollbar ~= false then
		local thumb = AddContentScrollThumb(tabBar, tabBarLayout, main, jan, -8, 2)
		thumb.Name = "SidebarScrollThumb"
		thumb.Active = true
		local dragInput, startY, startCanvas
		jan:Add(thumb.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragInput, startY, startCanvas = input, input.Position.Y, tabBar.CanvasPosition.Y
			end
		end))
		jan:Add(UserInputService.InputChanged:Connect(function(input)
			if not dragInput then return end
			if input ~= dragInput and not (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
			local overflow = math.max(0, tabBar.AbsoluteCanvasSize.Y - tabBar.AbsoluteWindowSize.Y)
			local travel = math.max(1, tabBar.AbsoluteWindowSize.Y - 8 - thumb.AbsoluteSize.Y)
			tabBar.CanvasPosition = Vector2.new(0, math.clamp(startCanvas + (input.Position.Y - startY) * overflow / travel, 0, overflow))
		end))
		jan:Add(UserInputService.InputEnded:Connect(function(input) if input == dragInput then dragInput = nil end end))
	end

	local tabIndicatorLayer = Instance.new("Frame")
	tabIndicatorLayer.Name = "TabIndicatorLayer"
	tabIndicatorLayer.BackgroundTransparency = 1
	tabIndicatorLayer.ClipsDescendants = true
	tabIndicatorLayer.ZIndex = Z.Window
	tabIndicatorLayer.Position = tabBar.Position
	tabIndicatorLayer.Size = tabBar.Size
	tabIndicatorLayer.Parent = main

	local tabIndicator = Instance.new("Frame")
	tabIndicator.Name = "Indicator"
	tabIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
	tabIndicator.BackgroundTransparency = 1
	tabIndicator.BorderSizePixel = 0
	tabIndicator.ZIndex = Z.Window
	tabIndicator.Size = UDim2.new(1, 0, 0, 34)
	tabIndicator.Position = UDim2.new(0, 0, 0, 0)
	tabIndicator.Parent = tabIndicatorLayer
	Corner(tabIndicator, 10)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, margin + 144, 0, 58)
	divider.Size = UDim2.new(0, 1, 1, -(58 + margin))
	divider.ZIndex = Z.Content
	divider.Parent = main

	local contentX = margin + 144 + 16
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, contentX, 0, 58)
	content.Size = UDim2.new(1, -contentX - margin, 1, -(58 + margin))
	content.ZIndex = Z.Content
	content.Parent = main

	local resizeHandle = Instance.new("ImageButton")
	resizeHandle.Name = "ResizeHandle"
	resizeHandle.BackgroundTransparency = 1
	resizeHandle.AutoButtonColor = false
	resizeHandle.Image = "rbxassetid://120997033468887"
	BindTheme(resizeHandle, "ImageColor3", "TextDim")
	resizeHandle.ImageTransparency = 0.35
	resizeHandle.AnchorPoint = Vector2.new(1, 1)
	resizeHandle.Position = UDim2.new(1, -4, 1, -4)
	resizeHandle.Size = UDim2.fromOffset(16, 16)
	resizeHandle.ZIndex = Z.Content + 4
	resizeHandle.Parent = main

	jan:Add(resizeHandle.MouseEnter:Connect(function()
		Tween(resizeHandle, { ImageTransparency = 0 }, 0.12)
	end))
	jan:Add(resizeHandle.MouseLeave:Connect(function()
		Tween(resizeHandle, { ImageTransparency = 0.35 }, 0.12)
	end))

	Tween(main, { BackgroundTransparency = 0.15 }, 0.6, Enum.EasingStyle.Exponential)

	local self = setmetatable({
		_gui            = main,
		_content        = content,
		_tabBar         = tabBar,
		_tabIndicatorLayer = tabIndicatorLayer,
		_tabIndicator   = tabIndicator,
		_titleLabel     = titleLabel,
		_subLabel       = subLabel,
		_tabs           = {},
		_currentTab     = nil,
		_normalSize     = size,
		_fullscreen     = false,
		_janitor        = jan,
		_state          = "open",
		_busy           = false,
		_destroyed      = false,
		_searchIndex    = {},
		_useBlur        = opts.UseBlur ~= false,
		_defaultTabName = opts.DefaultTab,
		_tabChangeListeners = {},
	}, Window)

	table.insert(NullUI._Windows, self)

	if opts.Draggable ~= false then
		self._drag = SetupSmoothDrag(main, topbar, jan)
	end

	if opts.Resizable ~= false then
		SetupResize(main, resizeHandle, jan, {
			-- No mobile o minimo nao pode ser maior que a janela ja clampada, senao um
			-- resize devolve a janela pro tamanho cortado.
			MinSize = Vector2.new(
				math.min((opts.MinSize or Vector2.new(420, 300)).X, size.X.Offset),
				math.min((opts.MinSize or Vector2.new(420, 300)).Y, size.Y.Offset)
			),
			OnResize = function(newSize, finished)
				if self._fullscreen then return end
				if finished then
					self._normalSize = newSize
					self._sizeBeforeMinimize = newSize
				end
			end,
		})
	else
		resizeHandle.Visible = false
	end

	if self._useBlur then
		self._acrylic = CreateWindowAcrylic(main)
		jan:Add(self._acrylic)
	end

	jan:Add(closeBtn.MouseButton1Click:Connect(function()
		NullUI:Confirm({
			Title = "Close Window",
			Text = "Do you want to close this window? You will not be able to open it again. "
				.. "If you just want to hide it, use the minimize button instead.",
			ConfirmText = "Close Window",
			CancelText = "Cancel",
			Danger = true,
			Window = self,
			Callback = function(confirmed)
				if confirmed then self:Destroy() end
			end,
		})
	end))

	jan:Add(minBtn.MouseButton1Click:Connect(function() self:Toggle() end))
	jan:Add(fullBtn.MouseButton1Click:Connect(function() self:ToggleFullscreen() end))
	jan:Add(searchBtn.MouseButton1Click:Connect(function() self:_OpenSearch() end))

	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or KeybindCapturing then return end
		if self._state ~= "open" then return end
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
		if ctrlDown and input.KeyCode == Enum.KeyCode.K then
			self:_OpenSearch()
		end
	end))

	local toggleKey = opts.ToggleKeybind
	if toggleKey == nil then
		toggleKey = Enum.KeyCode.RightShift
	end

	if toggleKey then
		jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or KeybindCapturing then return end
			if UserInputService:GetFocusedTextBox() then return end
			if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == toggleKey then
				self:Toggle()
			end
		end))
	end

	if IsMobileDevice then
		local mobileToggle = Instance.new("ImageButton")
		mobileToggle.Name = "MobileToggleButton"
		mobileToggle.BackgroundColor3 = Color3.fromRGB(1, 1, 1)
		mobileToggle.BackgroundTransparency = 1
		mobileToggle.BorderSizePixel = 0
		-- Alinhado com a barra do Roblox: a ScreenGui comeca abaixo do inset, entao
		-- subir inset.Y coloca o botao na mesma faixa das pilulas do topo.
		local topInset  = GuiService:GetGuiInset().Y
		local toggleSize = 45
		local bandY = -(topInset / GetUIScale()) + ((topInset / GetUIScale()) - toggleSize) / 2

		mobileToggle.AnchorPoint = Vector2.new(0, 0)
		mobileToggle.Position = opts.TogglePosition or UDim2.fromOffset(300, math.floor(bandY))
		mobileToggle.Size = UDim2.fromOffset(toggleSize, toggleSize)
		mobileToggle.Image = "rbxassetid://136834285051667"
		mobileToggle.ZIndex = Z.Toast
		mobileToggle.Parent = root

		local mobileToggleCorner = Instance.new("UICorner")
		mobileToggleCorner.CornerRadius = UDim.new(1, 0)
		mobileToggleCorner.Parent = mobileToggle

		-- Draggable is deprecated and swallows touch input (Activated never fires),
		-- so drive the drag by hand and treat a touch that barely moved as a tap.
		local DRAG_SLOP = 8
		local dragInput, dragStart, startPos, dragged

		jan:Add(mobileToggle.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			if dragInput then return end
			dragInput = input
			dragStart = input.Position
			startPos  = mobileToggle.Position
			dragged   = false
		end))

		jan:Add(UserInputService.InputChanged:Connect(function(input)
			if input ~= dragInput or not dragStart then return end
			local delta = input.Position - dragStart
			if not dragged and delta.Magnitude > DRAG_SLOP then dragged = true end
			if not dragged then return end
			local s = GetUIScale()
			mobileToggle.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X / s,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y / s
			)
		end))

		jan:Add(UserInputService.InputEnded:Connect(function(input)
			if input ~= dragInput then return end
			dragInput, dragStart = nil, nil
			if not dragged then
				self:Toggle()
			end
		end))

		jan:Add(mobileToggle)
	elseif toggleKey then
		NullUI:Notify({
			Title = "Minimize Keybind",
			Text  = "Press " .. toggleKey.Name .. " to minimize or open this panel.",
			Type  = "info",
			Duration = 15,
		})
	end

	self:SetUserInfo(opts.UserInfo)
	return self
end

function Window:ResetLayout()
	if self._destroyed then return end
	CloseAnyOpenPopup()
	self._gui.Size = self._gui:GetAttribute("InitialSize")
	self._gui.Position = self._gui:GetAttribute("InitialPosition")
	self._normalSize = self._gui.Size
	self._sizeBeforeMinimize = self._gui.Size
	self._fullscreen = false
	if self._drag then self._drag.Sync() end
end

function Window:_RefreshFooter()
	if self._destroyed then return end
	local hasButtons = false
	if self._dock then
		for _, child in ipairs(self._dock:GetChildren()) do
			if child:IsA("GuiButton") and child.Visible then hasButtons = true; break end
		end
		self._dock.Visible = hasButtons
	end
	local showProfile = not hasButtons and self._UserInfoOptions.Enabled ~= false
	self._UserInfoFrame.Visible = showProfile
	local reserve = (hasButtons and 44) or (showProfile and 64) or 0
	local size = UDim2.new(0, 130, 1, -(58 + NullUI.Theme.Margin + reserve))
	self._tabBar.Size = size
	self._tabIndicatorLayer.Size = size
end

function Window:SetUserInfo(options)
	if self._destroyed then return end
	self._UserInfoOptions = self._UserInfoOptions or {Enabled = true, Avatar = "player", NameMode = "display"}
	for key, value in pairs(options or {}) do self._UserInfoOptions[key] = value end
	local settings = self._UserInfoOptions
	if not self._UserInfoFrame then
		local frame = Instance.new("Frame")
		frame.Name = "UserInfo"
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = Vector2.new(0, 1)
		frame.Position = UDim2.new(0, NullUI.Theme.Margin, 1, -NullUI.Theme.Margin)
		frame.Size = UDim2.fromOffset(130, 54)
		frame.ZIndex = Z.Content
		frame.Parent = self._gui
		local avatar = Instance.new("ImageLabel")
		avatar.BackgroundTransparency = 1
		avatar.Size = UDim2.fromOffset(40, 40)
		avatar.Position = UDim2.fromOffset(0, 7)
		avatar.ZIndex = Z.Content + 1
		avatar.Parent = frame
		Corner(avatar, 20)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.FontFace = NullUI.Theme.Font
		BindTheme(name, "TextColor3", "Text")
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(48, 9)
		name.Size = UDim2.new(1, -48, 0, 19)
		name.ZIndex = Z.Content + 1
		name.Parent = frame
		local username = name:Clone()
		username.FontFace = NullUI.Theme.FontRegular
		BindTheme(username, "TextColor3", "TextDim")
		username.TextSize = 12
		username.Position = UDim2.fromOffset(48, 30)
		username.Size = UDim2.new(1, -48, 0, 16)
		username.Parent = frame
		self._UserInfoFrame, self._UserAvatar, self._UserName, self._UserHandle = frame, avatar, name, username
	end
	local anonymous = settings.NameMode == "anonymous"
	self._UserName.Text = anonymous and "Anonymous" or (settings.NameMode == "username" and LocalPlayer.Name or LocalPlayer.DisplayName)
	self._UserHandle.Text = anonymous and "" or ("@" .. LocalPlayer.Name)
	self._UserHandle.Visible = not anonymous
	self._UserName.Position = UDim2.fromOffset(48, anonymous and 18 or 9)
	self._UserAvatarRevision = (self._UserAvatarRevision or 0) + 1
	local revision = self._UserAvatarRevision
	local image = tostring(settings.Avatar or "player")
	if image == "player" then
		self._UserAvatar.Image = ""
		task.spawn(function()
			local ok, url = pcall(function() return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end)
			if ok and not self._destroyed and self._UserAvatar.Parent and self._UserAvatarRevision == revision then self._UserAvatar.Image = url end
		end)
	else
		self._UserAvatar.Image = image:match("^%d+$") and ("rbxassetid://" .. image) or image
	end
	self:_RefreshFooter()
	return self
end

function Window:SetTitle(title, subtitle)
	if self._titleLabel then self._titleLabel.Text = title or self._titleLabel.Text end
	if subtitle and self._subLabel then self._subLabel.Text = subtitle end
end

function Window:IsOpen()
	return self._state == "open"
end

function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	local idx = table.find(NullUI._Windows, self)
	if idx then table.remove(NullUI._Windows, idx) end

	CloseAnyOpenPopup()

	local gui = self._gui

	Tween(gui, {
		Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, 0, 0),
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	Tween(gui, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

	task.delay(0.34, function()
		self._janitor:Destroy()
		if gui then gui:Destroy() end
	end)
end

function Window:Toggle()
	if self._destroyed or self._busy then return end
	if self._state == "open" then
		self:Close()
	else
		self:Open()
	end
end

function Window:Close()
	if self._destroyed or self._busy or self._state ~= "open" then return end
	self._busy = true
	self._state = "closed"

	CloseAnyOpenPopup()

	local gui = self._gui
	self._sizeBeforeMinimize = self._fullscreen
		and UDim2.new(0.94, 0, 0.9, 0)
		or (self._normalSize or gui.Size)

	Tween(gui, {
		Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, 0, 0),
	}, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	Tween(gui, { BackgroundTransparency = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

	task.delay(0.28, function()
		if self._destroyed then return end
		if self._state == "closed" and gui and gui.Parent then
			gui.Visible = false
		end
		self._busy = false
	end)

end

function Window:Open()
	if self._destroyed or self._busy or self._state ~= "closed" then return end
	self._busy = true
	self._state = "open"

	local gui = self._gui
	gui.Visible = true

	local targetSize = self._sizeBeforeMinimize or self._normalSize
	Tween(gui, {
		Size = targetSize,
		BackgroundTransparency = self._BackgroundTransparency or 0.15,
	}, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	task.delay(0.33, function()
		self._busy = false
		if self._drag then self._drag.Sync() end
	end)
end

function Window:ToggleFullscreen()
	if self._destroyed or self._fullscreenBusy or self._busy then return end
	self._fullscreenBusy = true
	local gui = self._gui
	self._fullscreen = not self._fullscreen

	CloseAnyOpenPopup()

	if self._fullscreen then
		self._preFullscreenPosition = gui.Position
		Tween(gui, {
			Size = UDim2.new(0.94, 0, 0.9, 0),
			Position = UDim2.fromScale(0.5, 0.5),
		}, 0.35, Enum.EasingStyle.Quint)
	else
		Tween(gui, {
			Size = self._normalSize,
			Position = self._preFullscreenPosition or UDim2.fromScale(0.5, 0.55),
		}, 0.35, Enum.EasingStyle.Quint)
	end

	task.delay(0.36, function()
		self._fullscreenBusy = false
		if self._drag then self._drag.Sync() end
	end)
end

function Window:AddTabLine()
	local holder = Instance.new("Frame")
	holder.Name = "TabLine"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 9)
	holder.ZIndex = Z.Content
	holder.Parent = self._tabBar

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 4, 0.5, 0)
	line.Size = UDim2.new(1, -8, 0, 1)
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BackgroundTransparency = 0.92
	line.BorderSizePixel = 0
	line.ZIndex = Z.Content
	line.Parent = holder

	return holder
end

local DOCK_ICON_SIZE = 28
local DOCK_HEIGHT    = 34

function Window:AddDockButton(opts)
	opts = opts or {}
	local jan = self._janitor
	local margin = NullUI.Theme.Margin

	if not self._dock then
		local shrunkSize = UDim2.new(0, 130, 1, -(58 + margin + DOCK_HEIGHT + 10))
		self._tabBar.Size = shrunkSize
		self._tabIndicatorLayer.Size = shrunkSize

		local dock = Instance.new("Frame")
		dock.Name = "Dock"
		dock.BackgroundTransparency = 1
		dock.AnchorPoint = Vector2.new(0, 1)
		dock.Position = UDim2.new(0, margin, 1, -margin)
		dock.Size = UDim2.new(0, 130, 0, DOCK_HEIGHT)
		dock.ZIndex = Z.Content
		dock.Parent = self._gui

		local dockLayout = Instance.new("UIListLayout")
		dockLayout.FillDirection = Enum.FillDirection.Horizontal
		dockLayout.Padding = UDim.new(0, 6)
		dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
		dockLayout.Parent = dock

		self._dock = dock
		jan:Add(dock.ChildRemoved:Connect(function() self:_RefreshFooter() end))
	end

	local btn = Instance.new("TextButton")
	btn.Name = opts.Name or "DockButton"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 0.95
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(DOCK_ICON_SIZE, DOCK_ICON_SIZE)
	btn.LayoutOrder = #self._dock:GetChildren()
	btn.ZIndex = Z.Content + 1
	btn.Parent = self._dock
	self:_RefreshFooter()
	jan:Add(btn:GetPropertyChangedSignal("Visible"):Connect(function() self:_RefreshFooter() end))
	Corner(btn, 8)

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = opts.Icon and ResolveIcon(opts.Icon) or ""
	BindTheme(icon, "ImageColor3", "TextDim")
	icon.Size = UDim2.fromOffset(15, 15)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = Z.Content + 2
	icon.Parent = btn

	local active = false

	jan:Add(btn.MouseEnter:Connect(function()
		if active then return end
		Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
		Tween(icon, { ImageColor3 = NullUI.Theme.Text }, 0.12)
	end))
	jan:Add(btn.MouseLeave:Connect(function()
		if active then return end
		Tween(btn, { BackgroundTransparency = 0.95 }, 0.12)
		Tween(icon, { ImageColor3 = NullUI.Theme.TextDim }, 0.12)
	end))
	jan:Add(btn.MouseButton1Click:Connect(function()
		if opts.Callback then task.spawn(opts.Callback) end
	end))

	return {
		Instance = btn,
		Icon = icon,
		SetActive = function(_, isActive)
			active = isActive and true or false
			Tween(btn, { BackgroundTransparency = active and 0.8 or 0.95 }, 0.12)
			Tween(icon, { ImageColor3 = active and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.12)
		end,
	}
end

function Window:AddPanelTab(opts)
	opts = opts or {}
	local self_ = self
	local tabObj = self:AddTab({
		Name   = opts.Name,
		Icon   = opts.Icon,
		Hidden = opts.Hidden ~= false,
	})
	tabObj._page.Visible = false
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end

	if opts.OnToggle then
		table.insert(self._tabChangeListeners, function(selected)
			task.spawn(opts.OnToggle, selected == tabObj)
		end)
	end

	local lastRealTab = nil
	local function openPanel()
		if self_._currentTab == tabObj then return end
		if self_._currentTab and not self_._currentTab.Hidden then
			lastRealTab = self_._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self_._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self_._tabs[1] and self_._tabs[1] ~= tabObj then
			self_._tabs[1]._select()
		end
	end

	return {
		Instance = tabObj._group,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self_._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self_._currentTab == tabObj end,
	}
end

function Window:AddDefaultCreditsPanel()
	local jan = self._janitor
	local dockBtn
	local panel = self:AddPanelTab({
		Name = "Credits",
		Icon = "Lucide:heart-handshake",
		OnToggle = function(isOpen)
			if dockBtn then dockBtn:SetActive(isOpen) end
		end,
	})

	local CREDITS = {
		{ Name = "Skinny",   Role = "~90% of the UI, and organization of the Touchline script and its functions", Color = Color3.fromRGB(120, 150, 255) },
		{ Name = "Shezz",    Role = "Sub-tabs, and suggestions for the UI and script", Color = Color3.fromRGB(110, 210, 170) },
		{ Name = "NoSkills", Role = "Suggestions for the UI, and developer of Touchline script functions", Color = Color3.fromRGB(190, 150, 255) },
		{ Name = "Luxy_00",  Role = "Mobile UI tester, and developer of Touchline script functions", Color = Color3.fromRGB(255, 190, 110) },
		{ Name = "Elusive",  Role = "Suggestions for the UI, and main contributor to getting it launched fast", Color = Color3.fromRGB(255, 140, 170) },
	}

	local HEADER_H = 38

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = panel.Instance

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header

	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -40, 1, 0)
	titleRow.ZIndex = Z.Content + 2
	titleRow.Parent = header

	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow

	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon("heart-handshake")
	BindTheme(titleIcon, "ImageColor3", "Text")
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = Z.Content + 3
	titleIcon.Parent = titleRow

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = "Credits"
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Content + 3
	titleLabel.Parent = titleRow

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.ZIndex = Z.Content + 2
	closeBtn.Parent = header

	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	BindTheme(closeIcon, "ImageColor3", "TextDim")
	closeIcon.Size = UDim2.fromOffset(13, 13)
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.ZIndex = Z.Content + 3
	closeIcon.Parent = closeBtn

	closeBtn.MouseEnter:Connect(function() BindTheme(closeIcon, "ImageColor3", "Text") end)
	closeBtn.MouseLeave:Connect(function() BindTheme(closeIcon, "ImageColor3", "TextDim") end)
	closeBtn.MouseButton1Click:Connect(function() panel.Close() end)

	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = panel.Instance

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, HEADER_H + 1)
	scroll.Size = UDim2.new(1, 0, 1, -(HEADER_H + 1))
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = Z.Content + 1
	scroll.Parent = panel.Instance

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 12)
	scrollPad.PaddingBottom = UDim.new(0, 12)
	scrollPad.PaddingLeft = UDim.new(0, 14)
	scrollPad.PaddingRight = UDim.new(0, 14)
	scrollPad.Parent = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	AddScrollbar(scroll)
	AddContentScrollThumb(scroll, listLayout, panel.Instance, jan)

	for i, credit in ipairs(CREDITS) do
		local row = Instance.new("Frame")
		row.Name = credit.Name
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = 0.96
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 60)
		row.ZIndex = Z.Content + 2
		row.Parent = scroll

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = Color3.new(1, 1, 1)
		rowStroke.Transparency = 0.94
		rowStroke.Thickness = 1
		rowStroke.Parent = row

		row.MouseEnter:Connect(function() row.BackgroundTransparency = 0.92 end)
		row.MouseLeave:Connect(function() row.BackgroundTransparency = 0.96 end)

		local avatar = Instance.new("Frame")
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 12, 0.5, 0)
		avatar.Size = UDim2.fromOffset(38, 38)
		avatar.BackgroundColor3 = credit.Color
		avatar.BackgroundTransparency = 0.82
		avatar.BorderSizePixel = 0
		avatar.ZIndex = Z.Content + 2
		avatar.Parent = row

		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avatar

		local avStroke = Instance.new("UIStroke")
		avStroke.Color = credit.Color
		avStroke.Transparency = 0.55
		avStroke.Thickness = 1
		avStroke.Parent = avatar

		local avIcon = Instance.new("ImageLabel")
		avIcon.BackgroundTransparency = 1
		avIcon.Image = ResolveIcon("user-round")
		avIcon.ImageColor3 = credit.Color
		avIcon.Size = UDim2.fromOffset(17, 17)
		avIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		avIcon.Position = UDim2.fromScale(0.5, 0.5)
		avIcon.ZIndex = Z.Content + 3
		avIcon.Parent = avatar

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.FontFace = NullUI.Theme.Font
		nameLabel.Text = credit.Name
		BindTheme(nameLabel, "TextColor3", "Text")
		nameLabel.TextSize = 13.5
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Position = UDim2.fromOffset(62, 8)
		nameLabel.Size = UDim2.new(1, -74, 0, 16)
		nameLabel.ZIndex = Z.Content + 2
		nameLabel.Parent = row

		local roleLabel = Instance.new("TextLabel")
		roleLabel.BackgroundTransparency = 1
		roleLabel.FontFace = NullUI.Theme.FontRegular
		roleLabel.Text = credit.Role
		BindTheme(roleLabel, "TextColor3", "TextDim")
		roleLabel.TextSize = 11.5
		roleLabel.TextWrapped = true
		roleLabel.TextXAlignment = Enum.TextXAlignment.Left
		roleLabel.TextYAlignment = Enum.TextYAlignment.Top
		roleLabel.Position = UDim2.fromOffset(62, 25)
		roleLabel.Size = UDim2.new(1, -74, 0, 28)
		roleLabel.ZIndex = Z.Content + 2
		roleLabel.Parent = row
	end

	dockBtn = self:AddDockButton({
		Icon = "Lucide:heart-handshake",
		Callback = function() panel.Toggle() end,
	})

	return panel
end

local TRANSITION_EXIT  = 0.28
local TRANSITION_GAP   = 0.06
local TRANSITION_ENTER = 0.46

function Window:AddTab(nameOrOpts)
	local opts = type(nameOrOpts) == "table" and nameOrOpts or { Name = nameOrOpts }
	local name = opts.Name or opts.Title or "Tab"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or nil
	local hasIcon = iconAsset ~= nil and iconAsset ~= ""
	local jan = self._janitor

	local hidden = opts.Hidden == true

	local tabButton = Instance.new("TextButton")
	tabButton.Name = name
	tabButton.Text = ""
	tabButton.AutoButtonColor = false
	tabButton.BackgroundColor3 = Color3.new(1, 1, 1)
	tabButton.BackgroundTransparency = 1
	tabButton.BorderSizePixel = 0
	tabButton.Size = UDim2.new(1, 0, 0, 34)
	tabButton.ZIndex = Z.Content
	if not hidden then
		tabButton.Parent = self._tabBar
	end
	Corner(tabButton, 10)

	local isPrivate = opts.Password ~= nil and opts.Password ~= ""
	local remembered = isPrivate and IsPrivateTabRemembered(name)
	local unlocked = not isPrivate or remembered
	local glowColor = opts.GlowColor or NullUI.Theme.Accent
	local glowStroke, lockBadge, glowPulse

	if isPrivate then
		glowStroke = Stroke(tabButton, glowColor, 1, remembered and 0.9 or 0.82)

		if not remembered then
			glowPulse = TweenService:Create(
				glowStroke,
				TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.94 }
			)
			glowPulse:Play()
		end
	end

	if isPrivate and not remembered then
		lockBadge = Instance.new("Frame")
		lockBadge.Name = "LockBadge"
		BindTheme(lockBadge, "BackgroundColor3", "Background")
		lockBadge.BackgroundTransparency = 0
		lockBadge.BorderSizePixel = 0
		lockBadge.Size = UDim2.fromOffset(13, 13)
		lockBadge.AnchorPoint = Vector2.new(1, 0)
		lockBadge.Position = UDim2.new(1, -2, 0, -3)
		lockBadge.ZIndex = Z.Content + 3
		lockBadge.Parent = tabButton
		Corner(lockBadge, 7)
		Stroke(lockBadge, glowColor, 1, 0.7)

		local lockIcon = Instance.new("ImageLabel")
		lockIcon.BackgroundTransparency = 1
		lockIcon.Image = ResolveIcon("lock")
		lockIcon.ImageColor3 = glowColor
		lockIcon.Size = UDim2.fromOffset(7, 7)
		lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		lockIcon.Position = UDim2.fromScale(0.5, 0.5)
		lockIcon.ZIndex = Z.Content + 4
		lockIcon.Parent = lockBadge
	end

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = Z.Content
	row.Parent = tabButton

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 12)
	rowPad.PaddingRight = UDim.new(0, 12)
	rowPad.Parent = row

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local iconLabel
	if hasIcon then
		iconLabel = Instance.new("ImageLabel")
		iconLabel.Name = "Icon"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Image = iconAsset
		BindTheme(iconLabel, "ImageColor3", "TextDim")
		iconLabel.Size = UDim2.fromOffset(16, 16)
		iconLabel.LayoutOrder = 1
		iconLabel.ZIndex = Z.Content + 1
		iconLabel.Parent = row
	end

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = NullUI.Theme.Font
	textLabel.Text = name
	BindTheme(textLabel, "TextColor3", "TextDim")
	textLabel.TextSize = 14
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextTruncate = Enum.TextTruncate.AtEnd
	textLabel.Size = UDim2.new(1, hasIcon and -26 or 0, 1, 0)
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = Z.Content + 1
	textLabel.Parent = row

	local pageGroup = Instance.new("Frame")
	pageGroup.ClipsDescendants = true
	pageGroup.Name = name .. "Group"
	pageGroup.BackgroundTransparency = 1
	pageGroup.Size = UDim2.fromScale(1, 1)
	pageGroup.Visible = false
	pageGroup.ZIndex = Z.Content
	pageGroup.Parent = self._content

	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.fromScale(1, 1)
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.ScrollBarThickness = 0
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.ZIndex = Z.Content
	page.Parent = pageGroup

	local pagePad = Instance.new("UIPadding")
	pagePad.Name = "PagePadding"
	pagePad.PaddingRight = UDim.new(0, 12)
	pagePad.PaddingBottom = UDim.new(0, 6)
	pagePad.Parent = page

	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Name = "PageLayout"
	pageLayout.Padding = UDim.new(0, 8)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = page

	AddScrollbar(page)
	AddContentScrollThumb(page, pageLayout, pageGroup, jan)
	AddEmptyState(page, pageGroup, jan)

	local tabObj = setmetatable({
		Name      = name,
		_page     = page,
		_group    = pageGroup,
		_button   = tabButton,
		_icon     = iconLabel,
		_label    = textLabel,
		_window   = self,
		_janitor  = jan,
		_password = opts.Password,
	}, Tab)

	local myIndex = #self._tabs + 1

	local function indicatorY()
		return (tabButton.AbsolutePosition.Y - self._tabBar.AbsolutePosition.Y) / GetUIScale()
	end

	local function selectTab()
		if tabObj._SidebarGroup then tabObj._SidebarGroup:SetCollapsed(false) end
		self._tabIndicator.Visible = not hidden
		if self._currentTab == tabObj then return end

		self._tabSwitchToken = (self._tabSwitchToken or 0) + 1
		local myToken = self._tabSwitchToken

		local direction = 0
		if self._currentIndex then
			direction = (myIndex > self._currentIndex) and 1 or -1
		end
		self._currentIndex = myIndex

		local previousTab = self._currentTab
		self._currentTab = tabObj
		for _, fn in ipairs(self._tabChangeListeners) do
			task.spawn(fn, tabObj)
		end

		for _, t in pairs(self._tabs) do
			local isSelected = (t == tabObj)
			Tween(t._label, { TextColor3 = isSelected and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.22)
			if t._icon then
				Tween(t._icon, { ImageColor3 = isSelected and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.22)
			end
			if not isSelected then
				Tween(t._button, { BackgroundTransparency = 1 }, 0.15)
			end
		end

		if hidden then
			Tween(self._tabIndicator, { BackgroundTransparency = 1 }, 0.15)
		else
			if self._indicatorTween then self._indicatorTween:Cancel() end
   if not previousTab then
    self._tabIndicator.Position = UDim2.new(0, 0, 0, indicatorY())
   end
   self._tabIndicator.BackgroundTransparency = 0.88
   self._indicatorTween = Tween(self._tabIndicator, {
				Position = UDim2.new(0, 0, 0, indicatorY()),
			}, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end

		for _, t in pairs(self._tabs) do
			if t ~= tabObj and t ~= previousTab and t._group.Visible then
				t._group.Visible = false
			end
		end

		local function playEnter()
			if self._tabSwitchToken ~= myToken then return end
			pageGroup.Visible = true
					pageGroup.Position = UDim2.fromOffset(direction * 20, 0)
			Tween(pageGroup, {
				Position = UDim2.fromOffset(0, 0),
			}, TRANSITION_ENTER, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end

		if previousTab and previousTab._group.Visible then
			local g = previousTab._group
			Tween(g, {
				Position = UDim2.fromOffset(-direction * 20, 0),
			}, TRANSITION_EXIT, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(TRANSITION_EXIT, function()
				if self._tabSwitchToken ~= myToken then return end
				if g then g.Visible = false end
				task.delay(TRANSITION_GAP, playEnter)
			end)
		else
			playEnter()
		end
	end

	local promptOpen = false
	local function guardedSelect()
		if isPrivate and not unlocked then
			if promptOpen then return end
			promptOpen = true
			self:_PromptTabPassword(tabObj, function(success, remember)
				promptOpen = false
				if not success then return end
				SetPrivateTabRemembered(tabObj.Name, remember == true)
				unlocked = true
				tabObj.Unlocked = true
				if glowPulse then glowPulse:Cancel() end
				if glowStroke then Tween(glowStroke, { Transparency = 0.9 }, 0.4) end
				if lockBadge then
					Tween(lockBadge, { BackgroundTransparency = 1 }, 0.25)
					task.delay(0.25, function()
						if lockBadge then lockBadge:Destroy(); lockBadge = nil end
					end)
				end
				selectTab()
			end)
			return
		end
		selectTab()
	end

	tabObj._select = guardedSelect
	tabObj.IsPrivate = isPrivate
	tabObj.Unlocked = unlocked
	tabObj.Hidden = hidden

	if not hidden then
  local lastIndicatorY
  jan:Add(tabButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
   if self._currentTab ~= tabObj then return end
   local y = indicatorY()
   if lastIndicatorY and math.abs(y - lastIndicatorY) < 0.01 then return end
   lastIndicatorY = y
   if self._indicatorTween then self._indicatorTween:Cancel(); self._indicatorTween = nil end
   self._tabIndicator.BackgroundTransparency = 0.88
   self._tabIndicator.Position = UDim2.new(0, 0, 0, y)
  end))

		jan:Add(tabButton.MouseButton1Click:Connect(guardedSelect))

		jan:Add(tabButton.MouseEnter:Connect(function()
			if self._currentTab ~= tabObj then
				Tween(tabButton, { BackgroundTransparency = 0.95 }, 0.15)
			end
		end))
		jan:Add(tabButton.MouseLeave:Connect(function()
			if self._currentTab ~= tabObj then
				Tween(tabButton, { BackgroundTransparency = 1 }, 0.15)
			end
		end))
	end

	table.insert(self._tabs, tabObj)
	if not hidden then

		self._visibleTabCount = (self._visibleTabCount or 0) + 1
		if self._visibleTabCount == 1 then
			guardedSelect()
		end
		if self._defaultTabName and name == self._defaultTabName then
			guardedSelect()
		end
	end

	return tabObj
end

function Window:AddPrivateTab(opts)
	opts = type(opts) == "table" and opts or { Name = opts }
	assert(opts.Password and opts.Password ~= "", "AddPrivateTab requires opts.Password")
	return self:AddTab(opts)
end

function Window:_PromptTabPassword(tabObj, callback)
	local root = NullUI._Root
	local jan = Janitor.new()
	local closed = false
	local settled = false

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "TabPasswordBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root

	local dialog = Instance.new("Frame")
	dialog.Name = "TabPasswordDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(self._gui)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	BindTheme(dialog, "BackgroundColor3", "Background")
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 300, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	Corner(dialog, 14)
	local dialogStroke = Stroke(dialog, Color3.new(1, 1, 1), 1, 0.9)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = dialog

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = dialog

	local dialogLayout = Instance.new("UIListLayout")
	dialogLayout.Padding = UDim.new(0, 8)
	dialogLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dialogLayout.Parent = dialog

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.LayoutOrder = 1
	header.ZIndex = Z.ModalTop + 1
	header.Parent = dialog

	local lockIcon = Instance.new("ImageLabel")
	lockIcon.BackgroundTransparency = 1
	lockIcon.Image = ResolveIcon("lock")
	BindTheme(lockIcon, "ImageColor3", "TextDim")
	lockIcon.Size = UDim2.fromOffset(18, 18)
	lockIcon.Position = UDim2.fromOffset(0, 0)
	lockIcon.ZIndex = Z.ModalTop + 2
	lockIcon.Parent = header

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.FontFace = NullUI.Theme.Font
	title.Text = "Private Tab"
	BindTheme(title, "TextColor3", "Text")
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -26, 1, 0)
	title.Position = UDim2.fromOffset(26, 0)
	title.ZIndex = Z.ModalTop + 2
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.FontFace = NullUI.Theme.FontRegular
	subtitle.Text = ("Enter the password to unlock \"%s\""):format(tabObj.Name or "")
	BindTheme(subtitle, "TextColor3", "TextDim")
	subtitle.TextSize = 12
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.Size = UDim2.new(1, 0, 0, 0)
	subtitle.LayoutOrder = 2
	subtitle.ZIndex = Z.ModalTop + 1
	subtitle.Parent = dialog

	local fieldHolder = Instance.new("Frame")
	fieldHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	fieldHolder.BackgroundTransparency = 0.94
	fieldHolder.BorderSizePixel = 0
	fieldHolder.ClipsDescendants = true
	fieldHolder.Size = UDim2.new(1, 0, 0, 36)
	fieldHolder.LayoutOrder = 3
	fieldHolder.ZIndex = Z.ModalTop + 1
	fieldHolder.Parent = dialog
	Corner(fieldHolder, 8)
	local fieldStroke = Stroke(fieldHolder, Color3.new(1, 1, 1), 1, 0.88)

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.FontFace = NullUI.Theme.FontRegular
	box.PlaceholderText = ""
	box.Text = ""
	BindTheme(box, "TextColor3", "Text")
	box.TextTransparency = 1
	box.TextSize = 14
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(10, 0)
	box.Size = UDim2.new(1, -20, 1, 0)
	box.ZIndex = Z.ModalTop + 2
	box.Parent = fieldHolder

	local maskLabel = Instance.new("TextLabel")
	maskLabel.BackgroundTransparency = 1
	maskLabel.FontFace = NullUI.Theme.FontRegular
	maskLabel.Text = ""
	BindTheme(maskLabel, "TextColor3", "Text")
	maskLabel.TextSize = 14
	maskLabel.TextXAlignment = Enum.TextXAlignment.Left
	maskLabel.Position = box.Position
	maskLabel.Size = box.Size
	maskLabel.ZIndex = box.ZIndex + 1
	maskLabel.Parent = fieldHolder

	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.FontFace = NullUI.Theme.FontRegular
	placeholderLabel.Text = "Password"
	BindTheme(placeholderLabel, "TextColor3", "TextDim")
	placeholderLabel.TextSize = 14
	placeholderLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeholderLabel.Position = box.Position
	placeholderLabel.Size = box.Size
	placeholderLabel.ZIndex = box.ZIndex + 1
	placeholderLabel.Parent = fieldHolder

	jan:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		maskLabel.Text = string.rep("\226\128\162", #box.Text)
		placeholderLabel.Visible = (#box.Text == 0)
	end))

	local rememberRow = Instance.new("Frame")
	rememberRow.BackgroundTransparency = 1
	rememberRow.Size = UDim2.new(1, 0, 0, 18)
	rememberRow.LayoutOrder = 4
	rememberRow.ZIndex = Z.ModalTop + 1
	rememberRow.Parent = dialog

	local remember = IsPrivateTabRemembered(tabObj.Name)

	local rememberSwitch = Instance.new("Frame")
	rememberSwitch.AnchorPoint = Vector2.new(0, 0.5)
	rememberSwitch.Position = UDim2.new(0, 0, 0.5, 0)
	rememberSwitch.Size = UDim2.fromOffset(32, 18)
	rememberSwitch.BackgroundColor3 = remember and Color3.new(1, 1, 1) or Color3.fromRGB(60, 60, 60)
	rememberSwitch.BorderSizePixel = 0
	rememberSwitch.ZIndex = Z.ModalTop + 2
	rememberSwitch.Parent = rememberRow
	Corner(rememberSwitch, 9)

	local rememberLabel = Instance.new("TextLabel")
	rememberLabel.BackgroundTransparency = 1
	rememberLabel.FontFace = NullUI.Theme.FontRegular
	rememberLabel.Text = "Remember me"
	BindTheme(rememberLabel, "TextColor3", "TextDim")
	rememberLabel.TextSize = 12
	rememberLabel.TextXAlignment = Enum.TextXAlignment.Left
	rememberLabel.AnchorPoint = Vector2.new(0, 0.5)
	rememberLabel.Position = UDim2.new(0, 42, 0.5, 0)
	rememberLabel.Size = UDim2.new(1, -42, 1, 0)
	rememberLabel.ZIndex = Z.ModalTop + 2
	rememberLabel.Parent = rememberRow

	local rememberKnob = Instance.new("Frame")
	rememberKnob.Size = UDim2.fromOffset(14, 14)
	rememberKnob.AnchorPoint = Vector2.new(0, 0.5)
	rememberKnob.Position = remember and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	rememberKnob.BackgroundColor3 = remember and Color3.fromRGB(18, 18, 18) or Color3.new(1, 1, 1)
	rememberKnob.BorderSizePixel = 0
	rememberKnob.ZIndex = Z.ModalTop + 3
	rememberKnob.Parent = rememberSwitch
	Corner(rememberKnob, 7)

	local rememberClick = Instance.new("TextButton")
	rememberClick.Text = ""
	rememberClick.AutoButtonColor = false
	rememberClick.BackgroundTransparency = 1
	rememberClick.Size = UDim2.fromScale(1, 1)
	rememberClick.ZIndex = Z.ModalTop + 3
	rememberClick.Parent = rememberRow

	jan:Add(rememberClick.MouseButton1Click:Connect(function()
		remember = not remember
		Tween(rememberSwitch, {
			BackgroundColor3 = remember and Color3.new(1, 1, 1) or Color3.fromRGB(60, 60, 60),
		}, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		Tween(rememberKnob, {
			BackgroundColor3 = remember and Color3.fromRGB(18, 18, 18) or Color3.new(1, 1, 1),
			Position = remember and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	end))

	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 34)
	buttonsRow.LayoutOrder = 5
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow

	local function makeButton(text_, order, filled)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = filled and 0.82 or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, Color3.new(1, 1, 1), 1, filled and 0.7 or 0.85)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = NullUI.Theme.Font
		lbl.Text = text_
		BindTheme(lbl, "TextColor3", "Text")
		lbl.TextSize = 13
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn

		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max((filled and 0.82 or 1) - 0.1, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = filled and 0.82 or 1 }, 0.12)
		end))

		return btn
	end

	local cancelBtn  = makeButton("Cancel", 1, false)
	local unlockBtn  = makeButton("Unlock", 2, true)

	local function close(success)
		if closed then return end
		closed = true

		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		task.delay(0.16, function()
			jan:Destroy()
			backdrop:Destroy()
		end)

		task.spawn(callback, success, remember)
	end

	local function shakeError()
		Tween(fieldStroke, { Color = NullUI.Theme.Danger, Transparency = 0.4 }, 0.12)
		placeholderLabel.Text = "Incorrect password"
		Tween(placeholderLabel, { TextColor3 = NullUI.Theme.Danger }, 0.12)

		local baseX = dialog.Position.X.Offset
		local seq = { 8, -7, 5, -4, 0 }
		local t = 0
		for _, dx in ipairs(seq) do
			t = t + 0.05
			task.delay(t, function()
				if closed then return end
				Tween(dialog, {
					Position = UDim2.fromOffset(baseX + dx, dialog.Position.Y.Offset),
				}, 0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			end)
		end

		task.delay(1.4, function()
			if closed then return end
			Tween(fieldStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.3)
			Tween(placeholderLabel, { TextColor3 = NullUI.Theme.TextDim }, 0.3)
			task.delay(0.3, function()
				if not closed then placeholderLabel.Text = "Password" end
			end)
		end)
	end

	local function attempt()
		if closed or settled then return end
		if box.Text == tabObj._password then
			settled = true
			close(true)
		else
			shakeError()
			box.Text = ""
		end
	end

	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(unlockBtn.MouseButton1Click:Connect(attempt))
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))

	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if closed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			attempt()
		elseif input.KeyCode == Enum.KeyCode.Escape and not gameProcessed then
			close(false)
		end
	end))

	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	task.defer(function()
		if box.Parent then box:CaptureFocus() end
	end)
end

function Window:SelectTab(nameOrIndex)
	if type(nameOrIndex) == "number" then
		local t = self._tabs[nameOrIndex]
		if t then t._select() end
		return t
	end
	for _, t in ipairs(self._tabs) do
		if t.Name == nameOrIndex then
			t._select()
			return t
		end
	end
	return nil
end

function Window:_RegisterSearchable(tabObj, title, instance)
	if not title or title == "" or not instance then return end
	table.insert(self._searchIndex, { title = title, instance = instance, tabObj = tabObj })
end

local function SearchEntryPath(tabObj)
	if not tabObj then return "" end
	if tabObj._parentTabName then
		return tabObj._parentTabName .. " \226\128\186 " .. tabObj.Name
	end
	return tabObj.Name or ""
end

function Window:_JumpToSearchable(entry)
	local tabObj = entry.tabObj
	local inst = entry.instance
	if not tabObj or not inst or not inst.Parent then return end

	if tabObj._parentTab then
		tabObj._parentTab._select()
		tabObj._parentTab:SelectSubTab(tabObj._subTabIdx)
	elseif tabObj._select then
		tabObj._select()
	end

	task.delay(0.6, function()
		if not inst.Parent then return end
		local page = (tabObj._RootTab or tabObj)._page
		if not page then return end
		local targetY = math.max(
			0,
			(inst.AbsolutePosition.Y - page.AbsolutePosition.Y) + page.CanvasPosition.Y - 40
		)
		page.CanvasPosition = Vector2.new(page.CanvasPosition.X, targetY)

		local baseColor = inst.BackgroundColor3
		local baseBg = inst.BackgroundTransparency

		BindTheme(inst, "BackgroundColor3", "Accent")
		Tween(inst, { BackgroundTransparency = 0.85 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

		task.delay(0.5, function()
			if not inst.Parent then return end
			Tween(inst, { BackgroundTransparency = baseBg }, 0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
			task.delay(0.7, function()
				if inst.Parent then inst.BackgroundColor3 = baseColor end
			end)
		end)
	end)
end

function Window:JumpToElement(query)
	query = tostring(query or "")
	if query == "" then return false, "No element name given" end

	local q = query:lower()
	local best, bestScore = nil, 0
	for _, entry in ipairs(self._searchIndex) do
		local title = tostring(entry.title or ""):lower()
		if title == q then
			best, bestScore = entry, math.huge
			break
		elseif title:find(q, 1, true) then
			local score = 1000 - math.abs(#title - #q)
			if score > bestScore then best, bestScore = entry, score end
		end
	end

	if not best then
		return false, "No element found matching '" .. query .. "'"
	end

	self:_JumpToSearchable(best)
	return true, best.title
end

function Window:_OpenSearch()
	local self_ = self
	local root = NullUI._Root
	local panelW = math.min(440, ViewportSize().X / GetUIScale() - 40)
	local HEADER_H = 50
	local MAX_RESULTS_H = 280
	local ROW_H = 40

	local open = true
	local backdrop, panel, scale
	local heartbeatConn, textConn, focusConn
	local lastMatches = {}

	local restY

	local function closeSearch()
		if not open then return end
		open = false
		RegisterPopupClose(closeSearch)
		if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
		if textConn then textConn:Disconnect(); textConn = nil end
		if focusConn then focusConn:Disconnect(); focusConn = nil end

		local b, p = backdrop, panel
		backdrop, panel = nil, nil
		if p then
			Tween(p, { Size = UDim2.new(p.Size.X.Scale, p.Size.X.Offset, 0, 0) }, 0.32,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(p, { GroupTransparency = 1 }, 0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		end
		if b then Tween(b, { BackgroundTransparency = 1 }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.In) end
		task.delay(0.32, function()
			if b then b:Destroy() end
			if p then p:Destroy() end
		end)
	end

	RegisterPopupOpen(closeSearch)
	backdrop = MakePopupBackdrop(closeSearch)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	Tween(backdrop, { BackgroundTransparency = 0.4 }, 0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	panel = Instance.new("CanvasGroup")
	panel.Name = "SearchPalette"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(self_._gui)
		local s = GetUIScale()
		local px, py = math.round(cx / s), math.round(cy / s)
		restY = py
		panel.Position = UDim2.fromOffset(px, py - 18)
	end
	panel.Size = UDim2.new(0, panelW, 0, HEADER_H)
	BindTheme(panel, "BackgroundColor3", "Background")
	panel.BackgroundTransparency = 0.05
	panel.GroupTransparency = 1
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.ZIndex = Z.Modal
	panel.Parent = root
	Corner(panel, 14)
	Stroke(panel, Color3.new(1, 1, 1), 1, 0.8)
	GlassLayer(panel, 14, 0.985)

	scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = panel

	local searchIcon = Instance.new("ImageLabel")
	searchIcon.BackgroundTransparency = 1
	searchIcon.Image = ResolveIcon("search")
	BindTheme(searchIcon, "ImageColor3", "TextDim")
	searchIcon.Size = UDim2.fromOffset(16, 16)
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 16, 0, HEADER_H / 2)
	searchIcon.ZIndex = Z.Modal + 2
	searchIcon.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Size = UDim2.fromOffset(24, 24)
	closeBtn.Position = UDim2.new(1, -10, 0, HEADER_H / 2)
	closeBtn.ZIndex = Z.Modal + 2
	closeBtn.Parent = panel
	Corner(closeBtn, 7)

	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	BindTheme(closeIcon, "ImageColor3", "TextDim")
	closeIcon.Size = UDim2.fromOffset(12, 12)
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.ZIndex = Z.Modal + 3
	closeIcon.Parent = closeBtn

	closeBtn.MouseEnter:Connect(function()
		Tween(closeBtn, { BackgroundTransparency = 0.9 }, 0.12)
		Tween(closeIcon, { ImageColor3 = NullUI.Theme.Text }, 0.12)
	end)
	closeBtn.MouseLeave:Connect(function()
		Tween(closeBtn, { BackgroundTransparency = 1 }, 0.12)
		Tween(closeIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.12)
	end)
	closeBtn.MouseButton1Click:Connect(closeSearch)

	local box = Instance.new("TextBox")
	box.Name = "SearchBox"
	box.BackgroundTransparency = 1
	box.FontFace = NullUI.Theme.FontRegular
	box.PlaceholderText = "Search everything..."
	box.Text = ""
	BindTheme(box, "TextColor3", "Text")
	box.PlaceholderColor3 = NullUI.Theme.TextDim
	box.TextSize = 15
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.new(0, 40, 0, 0)
	box.Size = UDim2.new(1, -78, 0, HEADER_H)
	box.ZIndex = Z.Modal + 2
	box.Parent = panel

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, 0, 0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Visible = false
	divider.ZIndex = Z.Modal + 1
	divider.Parent = panel

	local resultsHolder = Instance.new("ScrollingFrame")
	resultsHolder.Name = "Results"
	resultsHolder.BackgroundTransparency = 1
	resultsHolder.BorderSizePixel = 0
	resultsHolder.Position = UDim2.new(0, 0, 0, HEADER_H + 1)
	resultsHolder.Size = UDim2.new(1, 0, 0, 0)
	resultsHolder.Visible = false
	resultsHolder.ScrollingDirection = Enum.ScrollingDirection.Y
	resultsHolder.ScrollBarThickness = 0
	resultsHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	resultsHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
	resultsHolder.ZIndex = Z.Modal + 1
	resultsHolder.Parent = panel

	local resultsPad = Instance.new("UIPadding")
	resultsPad.PaddingTop = UDim.new(0, 6)
	resultsPad.PaddingBottom = UDim.new(0, 6)
	resultsPad.PaddingLeft = UDim.new(0, 6)
	resultsPad.PaddingRight = UDim.new(0, 16)
	resultsPad.Parent = resultsHolder

	local resultsLayout = Instance.new("UIListLayout")
	resultsLayout.Padding = UDim.new(0, 2)
	resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resultsLayout.Parent = resultsHolder

	AddScrollbar(resultsHolder)
	AddContentScrollThumb(resultsHolder, resultsLayout, panel, {
		Add = function(_, conn) heartbeatConn = conn end,
	})

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = NullUI.Theme.FontRegular
	emptyLabel.Text = "No results"
	BindTheme(emptyLabel, "TextColor3", "TextDim")
	emptyLabel.TextSize = 13
	emptyLabel.Visible = false
	emptyLabel.Position = UDim2.new(0, 0, 0, HEADER_H + 9)
	emptyLabel.Size = UDim2.new(1, 0, 0, 26)
	emptyLabel.ZIndex = Z.Modal + 1
	emptyLabel.Parent = panel

	local function activate(entry)
		closeSearch()
		self_:_JumpToSearchable(entry)
	end

	local function rebuild(query)
		for _, child in ipairs(resultsHolder:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end

		local q = query:lower():match("^%s*(.-)%s*$")
		local matches = {}
		for _, entry in ipairs(self_._searchIndex) do
			if entry.instance and entry.instance.Parent then
				if q == "" or entry.title:lower():find(q, 1, true) then
					table.insert(matches, entry)
					if #matches >= 15 then break end
				end
			end
		end
		lastMatches = matches

		local showEmpty = (#matches == 0 and q ~= "")
		emptyLabel.Visible = showEmpty
		resultsHolder.Visible = (#matches > 0)
		divider.Visible = (#matches > 0) or showEmpty

		for i, entry in ipairs(matches) do
			local row = Instance.new("TextButton")
			row.Text = ""
			row.AutoButtonColor = false
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, ROW_H)
			row.LayoutOrder = i
			row.ZIndex = Z.Modal + 2
			row.Parent = resultsHolder
			Corner(row, 8)

			local titleLbl = Instance.new("TextLabel")
			titleLbl.BackgroundTransparency = 1
			titleLbl.FontFace = NullUI.Theme.Font
			titleLbl.Text = entry.title
			BindTheme(titleLbl, "TextColor3", "Text")
			titleLbl.TextSize = 13
			titleLbl.TextXAlignment = Enum.TextXAlignment.Left
			titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
			titleLbl.Position = UDim2.fromOffset(12, 5)
			titleLbl.Size = UDim2.new(1, -24, 0, 16)
			titleLbl.ZIndex = Z.Modal + 3
			titleLbl.Parent = row

			local pathLbl = Instance.new("TextLabel")
			pathLbl.BackgroundTransparency = 1
			pathLbl.FontFace = NullUI.Theme.FontRegular
			pathLbl.Text = SearchEntryPath(entry.tabObj)
			BindTheme(pathLbl, "TextColor3", "TextDim")
			pathLbl.TextSize = 11
			pathLbl.TextXAlignment = Enum.TextXAlignment.Left
			pathLbl.TextTruncate = Enum.TextTruncate.AtEnd
			pathLbl.Position = UDim2.fromOffset(12, 21)
			pathLbl.Size = UDim2.new(1, -24, 0, 12)
			pathLbl.ZIndex = Z.Modal + 3
			pathLbl.Parent = row

			row.MouseEnter:Connect(function()
				Tween(row, { BackgroundTransparency = 0.92 }, 0.1)
			end)
			row.MouseLeave:Connect(function()
				Tween(row, { BackgroundTransparency = 1 }, 0.1)
			end)
			row.MouseButton1Click:Connect(function()
				activate(entry)
			end)
		end

		local resultsH = math.min(#matches * (ROW_H + 2), MAX_RESULTS_H)

		local extraH = 0
		if resultsH > 0 then
			extraH = resultsH + 1
		elseif showEmpty then
			extraH = 36
		end

		Tween(resultsHolder, { Size = UDim2.new(1, 0, 0, resultsH) }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		Tween(panel, { Size = UDim2.new(0, panelW, 0, HEADER_H + extraH) }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	end

	local rebuildToken = 0
	textConn = box:GetPropertyChangedSignal("Text"):Connect(function()
		rebuildToken = rebuildToken + 1
		local myToken = rebuildToken
		local text = box.Text
		task.delay(0.12, function()
			if rebuildToken == myToken and box.Parent then
				rebuild(text)
			end
		end)
	end)

	focusConn = box.FocusLost:Connect(function(enterPressed)
		if enterPressed and lastMatches[1] then
			activate(lastMatches[1])
		end
	end)

	rebuild("")

	scale.Scale = 0.94
	Tween(panel, {
		GroupTransparency = 0,
		Position = UDim2.fromOffset(panel.Position.X.Offset, restY),
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Tween(scale, { Scale = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	task.defer(function()
		if box.Parent then box:CaptureFocus() end
	end)
end

local SUBTAB_EXIT  = 0.28
local SUBTAB_GAP   = 0.06
local SUBTAB_ENTER = 0.46

function Tab:AddSubTab(nameOrOpts)
	local opts = type(nameOrOpts) == "table" and nameOrOpts or { Name = nameOrOpts }
	local title = opts.Name or "SubTab"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or nil
	local jan = self._janitor

	self._subTabCount = (self._subTabCount or 0) + 1
	local idx = self._subTabCount

	if not self._subTabHolder then
		local page = self._page
		page.ScrollingEnabled = false
		page.AutomaticCanvasSize = Enum.AutomaticSize.None
		page.CanvasSize = UDim2.new(0, 0, 0, 0)

		local pl = page:FindFirstChildOfClass("UIListLayout")
		if pl then pl:Destroy() end
		local pp = page:FindFirstChildOfClass("UIPadding")
		if pp then pp:Destroy() end
		local oldTrack = page:FindFirstChild("ScrollTrack")
		if oldTrack then oldTrack:Destroy() end

		self._subTabHolder = Instance.new("ScrollingFrame")
		self._subTabHolder.Name = "SubTabBar"
		self._subTabHolder.Size = UDim2.new(1, -12, 0, 40)
		self._subTabHolder.Position = UDim2.fromOffset(2, 6)
		self._subTabHolder.BackgroundTransparency = 1
		self._subTabHolder.BorderSizePixel = 0
		self._subTabHolder.ScrollingDirection = Enum.ScrollingDirection.X
		self._subTabHolder.ScrollBarThickness = 0
		self._subTabHolder.AutomaticCanvasSize = Enum.AutomaticSize.X
		self._subTabHolder.CanvasSize = UDim2.new(0, 0, 0, 40)
		self._subTabHolder.ZIndex = Z.Content
		self._subTabHolder.Parent = page
		AddScrollbar(self._subTabHolder)

		self._subTabIndicatorLayer = Instance.new("Frame")
		self._subTabIndicatorLayer.Name = "SubTabIndicatorLayer"
		self._subTabIndicatorLayer.BackgroundTransparency = 1
		self._subTabIndicatorLayer.ClipsDescendants = true
		self._subTabIndicatorLayer.ZIndex = Z.Window
		self._subTabIndicatorLayer.Position = self._subTabHolder.Position
		self._subTabIndicatorLayer.Size = self._subTabHolder.Size
		self._subTabIndicatorLayer.Parent = page

		self._subTabIndicator = Instance.new("Frame")
		self._subTabIndicator.Name = "Indicator"
		self._subTabIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
		self._subTabIndicator.BackgroundTransparency = 1
		self._subTabIndicator.BorderSizePixel = 0
		self._subTabIndicator.ZIndex = Z.Window
		self._subTabIndicator.Size = UDim2.fromOffset(0, 32)
		self._subTabIndicator.Position = UDim2.fromOffset(0, 4)
		self._subTabIndicator.Parent = self._subTabIndicatorLayer
		Corner(self._subTabIndicator, 8)

		local sl = Instance.new("UIListLayout")
		sl.FillDirection = Enum.FillDirection.Horizontal
		sl.VerticalAlignment = Enum.VerticalAlignment.Center
		sl.Padding = UDim.new(0, 6)
		sl.SortOrder = Enum.SortOrder.LayoutOrder
		sl.Parent = self._subTabHolder

		self._subTabBody = Instance.new("Frame")
		self._subTabBody.Name = "SubTabBody"
		self._subTabBody.Size = UDim2.new(1, -4, 1, -62)
		self._subTabBody.Position = UDim2.fromOffset(2, 56)
		self._subTabBody.BackgroundTransparency = 1
		self._subTabBody.BorderSizePixel = 0
		self._subTabBody.ClipsDescendants = true
		self._subTabBody.ZIndex = Z.Content
		self._subTabBody.Parent = page

		self._subTabScrollTrack = Instance.new("Frame")
		self._subTabScrollTrack.Name = "SubTabScrollTrack"
		BindTheme(self._subTabScrollTrack, "BackgroundColor3", "TextDim")
		self._subTabScrollTrack.BackgroundTransparency = 0.85
		self._subTabScrollTrack.BorderSizePixel = 0
		self._subTabScrollTrack.Position = UDim2.new(0, 2, 0, 48)
		self._subTabScrollTrack.Size = UDim2.new(1, -12, 0, 3)
		self._subTabScrollTrack.Visible = false
		self._subTabScrollTrack.ZIndex = Z.Content
		self._subTabScrollTrack.Parent = page
		Corner(self._subTabScrollTrack, 2)

		self._subTabScrollThumb = Instance.new("Frame")
		self._subTabScrollThumb.Name = "Thumb"
		BindTheme(self._subTabScrollThumb, "BackgroundColor3", "TextDim")
		self._subTabScrollThumb.BackgroundTransparency = 0.35
		self._subTabScrollThumb.BorderSizePixel = 0
		self._subTabScrollThumb.Size = UDim2.new(0, 40, 1, 0)
		self._subTabScrollThumb.ZIndex = Z.Content + 1
		self._subTabScrollThumb.Parent = self._subTabScrollTrack
		Corner(self._subTabScrollThumb, 2)

		function self._updateSubTabScrollbar()
			local holder = self._subTabHolder
			local track = self._subTabScrollTrack
			if not holder or not track then return end
			if not self._group or not self._group.Visible then
				track.Visible = false
				return
			end
			local windowW = holder.AbsoluteWindowSize.X
			local canvasW = holder.AbsoluteCanvasSize.X
			local overflow = canvasW - windowW
			if overflow <= 1 or windowW <= 0 then
				track.Visible = false
				return
			end
			track.Visible = true
			local trackW = track.AbsoluteSize.X
			if trackW <= 0 then return end
			local thumbW = math.min(trackW, math.max(30, trackW * (windowW / canvasW)))
			local maxThumbX = trackW - thumbW
			local ratio = math.clamp(holder.CanvasPosition.X / overflow, 0, 1)
			self._subTabScrollThumb.Size = UDim2.new(thumbW / trackW, 0, 1, 0)
			self._subTabScrollThumb.Position = UDim2.new((maxThumbX / trackW) * ratio, 0, 0, 0)
		end

		jan:Add(ObserveProperties({
			{self._subTabHolder, "AbsoluteWindowSize", "AbsoluteCanvasSize", "CanvasPosition"},
			{self._subTabScrollTrack, "AbsoluteSize"},
			{self._group, "Visible"},
		}, self._updateSubTabScrollbar))

		self._subTabs = {}

		function self._syncSubIndicator(animated)
			local sel = self._subTabs and self._subTabs[self.SelectedSubTab]
			if not sel or not sel.Button.Parent then return end
			local holder = self._subTabHolder
			local s = GetUIScale()
			local relX = (sel.Button.AbsolutePosition.X - holder.AbsolutePosition.X) / s
			local w = sel.Button.AbsoluteSize.X / s
			if w <= 0 then return end
			local goal = {
				Position = UDim2.fromOffset(math.round(relX), 4),
				Size = UDim2.fromOffset(math.round(w), 32),
				BackgroundTransparency = 0.86,
			}
			if animated then
				Tween(self._subTabIndicator, goal, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			else
				self._subTabIndicator.Position = goal.Position
				self._subTabIndicator.Size = goal.Size
				self._subTabIndicator.BackgroundTransparency = goal.BackgroundTransparency
			end
		end

		jan:Add(self._subTabHolder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self._syncSubIndicator(false)
			self._updateSubTabScrollbar()
		end))
	end

	local btn = Instance.new("TextButton")
	btn.Name = "SubTab_" .. title:gsub("%s", "")
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutomaticSize = Enum.AutomaticSize.X
	btn.Size = UDim2.fromOffset(0, 32)
	btn.LayoutOrder = idx
	btn.ZIndex = Z.Content
	btn.Parent = self._subTabHolder
	Corner(btn, 8)

	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Padding = UDim.new(0, 6)
	bl.Parent = btn

	local bpad = Instance.new("UIPadding")
	bpad.PaddingLeft = UDim.new(0, 12)
	bpad.PaddingRight = UDim.new(0, 12)
	bpad.Parent = btn

	local ic = nil
	if iconAsset and iconAsset ~= "" then
		ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = iconAsset
		BindTheme(ic, "ImageColor3", "TextDim")
		ic.Size = UDim2.fromOffset(16, 16)
		ic.LayoutOrder = 1
		ic.ZIndex = Z.Content + 1
		ic.Parent = btn
	end

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = NullUI.Theme.Font
	lbl.Text = title
	BindTheme(lbl, "TextColor3", "TextDim")
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Size = UDim2.new(0, 0, 0, 32)
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.LayoutOrder = 2
	lbl.ZIndex = Z.Content + 1
	lbl.Parent = btn

	local group = Instance.new("Frame")
	group.Name = title .. "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Visible = false
	group.ZIndex = Z.Content
	group.Parent = self._subTabBody

	local container = Instance.new("ScrollingFrame")
	container.Name = title .. "Page"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ScrollingDirection = Enum.ScrollingDirection.Y
	container.ScrollBarThickness = 0
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.ZIndex = Z.Content
	container.Parent = group

	local cpad = Instance.new("UIPadding")
	cpad.Name = "PagePadding"
	cpad.PaddingRight = UDim.new(0, 12)
	cpad.PaddingBottom = UDim.new(0, 6)
	cpad.Parent = container

	local clayout = Instance.new("UIListLayout")
	clayout.Name = "PageLayout"
	clayout.Padding = UDim.new(0, 8)
	clayout.SortOrder = Enum.SortOrder.LayoutOrder
	clayout.Parent = container

	AddScrollbar(container)
	AddContentScrollThumb(container, clayout, group, jan)
	AddEmptyState(container, group, jan)

	local sub = setmetatable({
		Name           = title,
		_page          = container,
		_window        = self._window,
		_janitor       = jan,
		_parentTab     = self,
		_parentTabName = self.Name,
		_subTabIdx     = idx,
		Button    = btn,
		Label     = lbl,
		Icon      = ic,
		Container = container,
		Group     = group,
		Selected  = false,
	}, Tab)

	self._subTabs[idx] = sub

	jan:Add(btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if self.SelectedSubTab == idx then
			self._syncSubIndicator(false)
		end
	end))
	jan:Add(btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.SelectedSubTab == idx then
			self._syncSubIndicator(false)
		end
	end))

	jan:Add(btn.MouseEnter:Connect(function()
		if idx ~= self.SelectedSubTab then
			Tween(btn, { BackgroundTransparency = 0.94 }, 0.15)
		end
	end))
	jan:Add(btn.MouseLeave:Connect(function()
		if idx ~= self.SelectedSubTab then
			Tween(btn, { BackgroundTransparency = 1 }, 0.15)
		end
	end))

	local downPos = nil
	jan:Add(btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			downPos = input.Position
		end
	end))
	jan:Add(btn.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) and downPos then
			if (input.Position - downPos).Magnitude < DRAG_THRESHOLD then
				self:SelectSubTab(idx)
			end
			downPos = nil
		end
	end))

	if not self.SelectedSubTab then
		self:SelectSubTab(idx)
	end

	return sub
end

function Tab:SelectSubTab(idx)
	if not self._subTabs then return end
	local previous = self.SelectedSubTab
	if previous == idx then return end

	self._subTabSwitchToken = (self._subTabSwitchToken or 0) + 1
	local myToken = self._subTabSwitchToken

	local direction = 0
	if previous then
		direction = (idx > previous) and 1 or -1
	end

	self.SelectedSubTab = idx
	local target = self._subTabs[idx]
	local previousSub = previous and self._subTabs[previous]
	if not target then return end

	self._syncSubIndicator(previous ~= nil)

	for i, st in pairs(self._subTabs) do
		local sel = (i == idx)
		st.Selected = sel
		if not sel then
			Tween(st.Button, { BackgroundTransparency = 1 }, 0.15)
		end
		Tween(st.Label, { TextColor3 = sel and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.22)
		if st.Icon then
			Tween(st.Icon, { ImageColor3 = sel and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.22)
		end
	end

	for _, st in pairs(self._subTabs) do
		if st ~= target and st ~= previousSub and st.Group.Visible then
			st.Group.Visible = false
		end
	end

	local function playEnter()
		if self._subTabSwitchToken ~= myToken then return end
		target.Group.Visible = true
		target.Group.Position = UDim2.fromOffset(direction * 20, 0)
		Tween(target.Group, {
			Position = UDim2.fromOffset(0, 0),
		}, SUBTAB_ENTER, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end

	if previousSub and previousSub.Group.Visible then
		local g = previousSub.Group
		Tween(g, {
			Position = UDim2.fromOffset(-direction * 20, 0),
		}, SUBTAB_EXIT, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(SUBTAB_EXIT, function()
			if g then g.Visible = false end
			task.delay(SUBTAB_GAP, playEnter)
		end)
	else
		playEnter()
	end
end

function Tab:SelectSubTabByName(name)
	if not self._subTabs then return nil end
	for idx, st in pairs(self._subTabs) do
		if st.Name == name then
			self:SelectSubTab(idx)
			return st
		end
	end
	return nil
end

local function RegisterFlag(opts, api, kind)
	if opts.Flag then
		NullUI.Flags[opts.Flag] = api
		api.Flag = opts.Flag
		api.Kind = kind
		api.Label = opts.Text or opts.Label or opts.Flag
	end
	return api
end

function Tab:AddLabel(text)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = NullUI.Theme.FontRegular
	label.Text = text
	BindTheme(label, "TextColor3", "TextDim")
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 16)
	label.ZIndex = Z.Content
	label.Parent = self._page

	return {
		Instance = label,
		Set = function(_, v) label.Text = v end,
		Get = function() return label.Text end,
		Destroy = function() label:Destroy() end,
	}
end

function Tab:AddSection(textOrOpts, maybeIcon)
	local opts = type(textOrOpts) == "table" and textOrOpts or { Text = textOrOpts, Icon = maybeIcon }
	local text = opts.Text or "Section"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or ""

	local holder = Instance.new("Frame")
	holder.Name = "Section"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 24)
	holder.ZIndex = Z.Content
	holder.Parent = self._page

	local x = 2
	if iconAsset ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = iconAsset
		BindTheme(img, "ImageColor3", "TextDim")
		img.Size = UDim2.fromOffset(13, 13)
		img.Position = UDim2.fromOffset(2, 8)
		img.ZIndex = Z.Content + 1
		img.Parent = holder
		x = 2 + 13 + 7
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = NullUI.Theme.Font
	label.Text = string.upper(text)
	BindTheme(label, "TextColor3", "TextDim")
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(x, 8)
	label.Size = UDim2.new(1, -(x + 2), 0, 14)
	label.ZIndex = Z.Content + 1
	label.Parent = holder

	return {
		Instance = holder,
		Set = function(_, v) label.Text = string.upper(v) end,
		Destroy = function() holder:Destroy() end,
	}
end

function Tab:AddDivider()
	local holder = Instance.new("Frame")
	holder.Name = "Divider"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 13)
	holder.ZIndex = Z.Content
	holder.Parent = self._page

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BackgroundTransparency = 0.92
	line.BorderSizePixel = 0
	line.ZIndex = Z.Content
	line.Parent = holder

	return { Instance = holder, Destroy = function() holder:Destroy() end }
end

Tab.AddLine = Tab.AddDivider

function Tab:AddLineText(text)
	text = tostring(text or "")

	local holder = Instance.new("Frame")
	holder.Name = "LineText"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 20)
	holder.ZIndex = Z.Content
	holder.Parent = self._page

	local left = Instance.new("Frame")
	left.Name = "Left"
	left.AnchorPoint = Vector2.new(0, 0.5)
	left.Position = UDim2.fromScale(0, 0.5)
	left.Size = UDim2.new(0.5, -10, 0, 1)
	left.BackgroundColor3 = Color3.new(1, 1, 1)
	left.BackgroundTransparency = 0.92
	left.BorderSizePixel = 0
	left.ZIndex = Z.Content
	left.Parent = holder

	local right = Instance.new("Frame")
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.fromScale(1, 0.5)
	right.Size = UDim2.new(0.5, -10, 0, 1)
	right.BackgroundColor3 = Color3.new(1, 1, 1)
	right.BackgroundTransparency = 0.92
	right.BorderSizePixel = 0
	right.ZIndex = Z.Content
	right.Parent = holder

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.FontFace = NullUI.Theme.FontRegular
	label.Text = text
	BindTheme(label, "TextColor3", "TextDim")
	label.TextSize = 12
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 16)
	label.ZIndex = Z.Content + 1
	label.Parent = holder

	local gap = 10
	local minSide = 6
	local lastW = -1

	local function relayout()
		local w = holder.AbsoluteSize.X / GetUIScale()
		if w <= 0 or math.abs(w - lastW) < 1 then return end
		lastW = w

		local textW = MeasureText(text, 12, w)
		local sideW = math.max((w - textW) / 2 - gap, minSide)
		left.Size = UDim2.new(0, sideW, 0, 1)
		right.Size = UDim2.new(0, sideW, 0, 1)
	end

	BindWidthLayout(holder, relayout)
	task.defer(relayout)

	return {
		Instance = holder,
		Set = function(_, v)
			text = tostring(v or "")
			label.Text = text
			lastW = -1
			relayout()
		end,
		Destroy = function() holder:Destroy() end,
	}
end

function Tab:AddParagraph(opts)
	opts = opts or {}

	local card = BaseCard(self._page, 10)
	card.AutomaticSize = Enum.AutomaticSize.Y

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local titleLabel
	if opts.Title then
		local titleRow = Instance.new("Frame")
		titleRow.BackgroundTransparency = 1
		titleRow.Size = UDim2.new(1, 0, 0, 18)
		titleRow.AutomaticSize = Enum.AutomaticSize.Y
		titleRow.LayoutOrder = 1
		titleRow.ZIndex = Z.Content + 1
		titleRow.Parent = card

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 7)
		rowLayout.Parent = titleRow

		local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or ""
		if iconAsset ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = iconAsset
			BindTheme(img, "ImageColor3", "Text")
			img.Size = UDim2.fromOffset(15, 15)
			img.LayoutOrder = 1
			img.ZIndex = Z.Content + 2
			img.Parent = titleRow
		end

		titleLabel = Instance.new("TextLabel")
		titleLabel.BackgroundTransparency = 1
		titleLabel.FontFace = NullUI.Theme.Font
		titleLabel.Text = opts.Title
		BindTheme(titleLabel, "TextColor3", "Text")
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		titleLabel.AutomaticSize = Enum.AutomaticSize.X
		titleLabel.Size = UDim2.fromOffset(0, 18)
		titleLabel.LayoutOrder = 2
		titleLabel.ZIndex = Z.Content + 2
		titleLabel.Parent = titleRow

		local titlePadding = Instance.new("UIPadding")
		titlePadding.PaddingTop = UDim.new(0, 2)
		titlePadding.Parent = titleLabel
	end

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = NullUI.Theme.FontRegular
	textLabel.Text = opts.Text or ""
	BindTheme(textLabel, "TextColor3", "TextDim")
	textLabel.TextSize = 13
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.Size = UDim2.new(1, 0, 0, 16)
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = Z.Content + 1
	textLabel.Parent = card

	return {
		Instance = card,
		Set = function(_, v) textLabel.Text = v end,
		Get = function() return textLabel.Text end,
		SetTitle = function(_, v) if titleLabel then titleLabel.Text = v end end,
		Destroy = function() card:Destroy() end,
	}
end

local function BuildStarRow(parent, layoutOrder, maxStars, starColor, starSize, default)
	local starOutline = ResolveIcon("Phosphor:star")
	local starFilled = ResolveIcon("Material:star")

	local row = Instance.new("Frame")
	row.Name = "Stars"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, starSize)
	row.LayoutOrder = layoutOrder
	row.ZIndex = Z.Content + 1
	row.Parent = parent

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local stars = {}
	local selected = math.clamp(default or 0, 0, maxStars)

	local function paint(previewCount)
		local count = previewCount or selected
		for i, button in ipairs(stars) do
			local on = i <= count
			button.Image = on and starFilled or starOutline
			Tween(button, { ImageColor3 = on and starColor or NullUI.Theme.TextDim }, 0.12)
		end
	end

	for i = 1, maxStars do
		local button = Instance.new("ImageButton")
		button.Name = "Star" .. i
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Image = starOutline
		BindTheme(button, "ImageColor3", "TextDim")
		button.Size = UDim2.fromOffset(starSize, starSize)
		button.LayoutOrder = i
		button.ZIndex = Z.Content + 2
		button.Parent = row

		button.MouseEnter:Connect(function() paint(i) end)
		button.MouseLeave:Connect(function() paint() end)
		button.MouseButton1Click:Connect(function()
			selected = i
			paint()
		end)

		stars[i] = button
	end
	paint()

	return {
		Row = row,
		Get = function() return selected end,
		Set = function(v)
			selected = math.clamp(v or 0, 0, maxStars)
			paint()
		end,
		Nudge = function()
			for _, button in ipairs(stars) do Tween(button, { Rotation = 8 }, 0.06) end
			task.delay(0.06, function()
				for _, button in ipairs(stars) do Tween(button, { Rotation = 0 }, 0.12) end
			end)
		end,
	}
end

local function NormalizeFeedbackText(text)
	local invisibleChars = {
		["\226\128\139"] = "", ["\226\128\142"] = "", ["\226\128\143"] = "",
		["\239\187\191"] = "", ["\194\173"] = "",
	}
	for char, replacement in pairs(invisibleChars) do
		text = text:gsub(char, replacement)
	end
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
	return text
end

local FeedbackEvasionPatterns = {
	{pattern = "d%s*i%s*s%s*c%s*o%s*r%s*d", name = "discord"},
	{pattern = "t%s*e%s*l%s*e%s*g%s*r%s*a%s*m", name = "telegram"},
	{pattern = "w%s*h%s*a%s*t%s*s%s*a%s*p%s*p", name = "whatsapp"},
	{pattern = "h%s*t%s*t%s*p", name = "http"},
	{pattern = "h%s*t%s*t%s*p%s*s", name = "https"},
	{pattern = "w%s*w%s*w", name = "www"},
	{pattern = "c%s*o%s*m", name = "com"},
	{pattern = "o%s*r%s*g", name = "org"},
	{pattern = "n%s*e%s*t", name = "net"},
	{pattern = ".%s*g%s*g", name = ".gg"},
	{pattern = ".%s*c%s*o%s*m", name = ".com"},
	{pattern = "/%s*i%s*n%s*v%s*i%s*t%s*e", name = "/invite"},
	{pattern = "d%s*o%s*t%s*%s*c%s*o%s*m", name = "dot com"},
	{pattern = "a%s*t%s*%s*%s*h%s*e%s*r%s*e", name = "@here"},
	{pattern = "a%s*t%s*%s*%s*e%s*v%s*e%s*r%s*y%s*o%s*n%s*e", name = "@everyone"},
}

local function DetectFeedbackEvasion(text)
	for _, evasion in ipairs(FeedbackEvasionPatterns) do
		if text:match(evasion.pattern) then
			return true, evasion.name
		end
	end
	local dotCount, slashCount = 0, 0
	for i = 1, #text do
		local char = text:sub(i, i)
		if char == "." then dotCount = dotCount + 1 end
		if char == "/" then slashCount = slashCount + 1 end
	end
	if dotCount >= 3 or slashCount >= 3 then
		return true, "suspicious link/invite"
	end
	return false, nil
end

local FeedbackAsciiMap = {
	["á"] = "a", ["à"] = "a", ["ã"] = "a", ["â"] = "a", ["ä"] = "a",
	["Á"] = "A", ["À"] = "A", ["Ã"] = "A", ["Â"] = "A", ["Ä"] = "A",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["É"] = "E", ["È"] = "E", ["Ê"] = "E", ["Ë"] = "E",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
	["Í"] = "I", ["Ì"] = "I", ["Î"] = "I", ["Ï"] = "I",
	["ó"] = "o", ["ò"] = "o", ["õ"] = "o", ["ô"] = "o", ["ö"] = "o",
	["Ó"] = "O", ["Ò"] = "O", ["Õ"] = "O", ["Ô"] = "O", ["Ö"] = "O",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["Ú"] = "U", ["Ù"] = "U", ["Û"] = "U", ["Ü"] = "U",
	["ç"] = "c", ["Ç"] = "C", ["ñ"] = "n", ["Ñ"] = "N",
	["°"] = " ", ["º"] = " ", ["ª"] = " ",
}

local FeedbackAllowedChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?;:()[]{}@#%&*+-=/_\"'"

local function SanitizeFeedbackText(text)
	if not text or text == "" then
		return "_No message_"
	end

	text = NormalizeFeedbackText(text)

	local hasEvasion, evasionType = DetectFeedbackEvasion(text)
	if hasEvasion then
		return "[Message blocked - " .. evasionType .. "]"
	end

	text = text:gsub("@everyone", "@\226\128\139everyone")
	text = text:gsub("@here", "@\226\128\139here")
	text = text:gsub("<@!?(%d+)>", "[user]")
	text = text:gsub("<@&(%d+)>", "[role]")

	text = text:gsub("d[iI][sS][cC][oO][rR][dD]%.?[gG][gG]%s*/?%s*[%w%-_]+", "[invite removed]")
	text = text:gsub("d[iI][sS][cC][oO][rR][dD]%.?[cC][oO][mM]%s*/?%s*[iI][nN][vV][iI][tT][eE]%s*/?%s*[%w%-_]+", "[invite removed]")
	text = text:gsub("https?%s*:%s*//%s*[%w%-%.]+%s*%.%s*[%w]+[%w%-%./?=&%%]*", "[link removed]")
	text = text:gsub("www%s*%.%s*[%w%-]+%s*%.%s*[%w]+", "[link removed]")
	text = text:gsub("t[eE][lL][eE][gG][rR][aA][mM]%.?%s*[mM][eE]%s*/%s*[%w%-_]+", "[invite removed]")

	for old, new in pairs(FeedbackAsciiMap) do
		text = text:gsub(old, new)
	end

	local cleaned = ""
	for i = 1, #text do
		local char = text:sub(i, i)
		if FeedbackAllowedChars:find(char, 1, true) then
			cleaned = cleaned .. char
		else
			cleaned = cleaned .. " "
		end
	end
	text = cleaned

	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")

	local hasEvasionAfter = DetectFeedbackEvasion(text)
	if hasEvasionAfter then
		return "[Message blocked - suspicious content]"
	end

	if #text > 500 then
		text = text:sub(1, 500) .. "..."
	end

	return text
end

function NullUI:SanitizeText(text, opts)
	opts = opts or {}
	local maxLength = opts.MaxLength or 500

	if not text or text == "" then
		return "", false, nil
	end

	local normalized = NormalizeFeedbackText(tostring(text))
	local hasEvasion, evasionType = DetectFeedbackEvasion(normalized)
	if hasEvasion then
		return "", true, evasionType
	end

	local cleaned = SanitizeFeedbackText(text)
	if cleaned == "_No message_" then
		return "", false, nil
	end
	if cleaned:find("^%[Message blocked") then
		return "", true, "blocked content"
	end

	if #cleaned > maxLength then
		cleaned = cleaned:sub(1, maxLength)
	end

	return cleaned, false, nil
end

local function BuildFeedbackRow(parent, layoutOrder, rowH, placeholder, buttonIcon)
	local row = Instance.new("Frame")
	row.Name = "Feedback"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, rowH)
	row.LayoutOrder = layoutOrder
	row.ZIndex = Z.Content + 1
	row.Parent = parent

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(rowH + 6), 1, 0)
	pill.ZIndex = Z.Content + 1
	pill.Parent = row
	Corner(pill, 9)
	local pillStroke = Stroke(pill, Color3.new(1, 1, 1), 1, 0.9)

	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.ClearTextOnFocus = false
	box.FontFace = NullUI.Theme.FontRegular
	box.PlaceholderText = placeholder or "Give us some feedback!"
	box.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
	box.Text = ""
	BindTheme(box, "TextColor3", "Text")
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ClipsDescendants = true
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = Z.Content + 2
	box.Parent = pill

	box.Focused:Connect(function()
		Tween(pillStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
	end)
	box.FocusLost:Connect(function()
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.9 }, 0.15)
	end)

	local sendBtn = Instance.new("TextButton")
	sendBtn.Name = "Send"
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(rowH, rowH)
	sendBtn.ZIndex = Z.Content + 1
	sendBtn.Parent = row
	Corner(sendBtn, 9)

	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon(buttonIcon or "send")
	BindTheme(sendIcon, "ImageColor3", "Text")
	sendIcon.Size = UDim2.fromOffset(12, 12)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = Z.Content + 2
	sendIcon.Parent = sendBtn

	sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end)
	sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end)

	return { Row = row, Box = box, SendBtn = sendBtn }
end

function Tab:AddRating(opts)
	opts = opts or {}
	local maxStars = math.max(1, opts.MaxStars or 5)
	local starColor = opts.StarColor or Color3.fromRGB(255, 196, 64)
	local hasTitle = opts.Title and opts.Title ~= ""

	local card = BaseCard(self._page, 10)
	card.AutomaticSize = Enum.AutomaticSize.Y

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	if hasTitle then
		local titleLabel = Instance.new("TextLabel")
		titleLabel.BackgroundTransparency = 1
		titleLabel.FontFace = NullUI.Theme.Font
		titleLabel.Text = opts.Title
		BindTheme(titleLabel, "TextColor3", "Text")
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Size = UDim2.new(1, 0, 0, 16)
		titleLabel.LayoutOrder = 1
		titleLabel.ZIndex = Z.Content + 1
		titleLabel.Parent = card

		self._window:_RegisterSearchable(self, opts.Title, card)
	end

	local starBar = BuildStarRow(card, 2, maxStars, starColor, 20, opts.Default)
	local feedback = BuildFeedbackRow(card, 3, 26, opts.Placeholder, opts.ButtonIcon)

	local clearOnSubmit = opts.ClearOnSubmit ~= false
	feedback.SendBtn.MouseButton1Click:Connect(function()
		local selected = starBar.Get()
		if selected <= 0 then
			starBar.Nudge()
			return
		end
		if opts.Callback then task.spawn(opts.Callback, selected, feedback.Box.Text) end
		if opts.WebhookUrl then
			task.spawn(function()
				NullUI:SendFeedbackWebhook(opts.WebhookUrl, selected, feedback.Box.Text, opts.WebhookOptions)
			end)
		end
		if clearOnSubmit then
			feedback.Box.Text = ""
			starBar.Set(opts.Default or 0)
		end
	end)

	return {
		Instance = card,
		Get = function() return starBar.Get(), feedback.Box.Text end,
		Set = function(_, newStars, newText)
			starBar.Set(newStars)
			if newText ~= nil then feedback.Box.Text = newText end
		end,
		Destroy = function() card:Destroy() end,
	}
end

function Tab:AddButton(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)

	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 44, opts.Text or "Button", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Button", card)

	local chev = Instance.new("ImageLabel")
	chev.BackgroundTransparency = 1
	chev.Image = ResolveIcon("chevron-right")
	BindTheme(chev, "ImageColor3", "TextDim")
	chev.Size = UDim2.fromOffset(14, 14)
	chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, -16, 0.5, 0)
	chev.ZIndex = Z.Content + 1
	chev.Parent = card

	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card

	click.MouseEnter:Connect(function()
		Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
		Tween(chev, { ImageColor3 = NullUI.Theme.Text, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
	end)
	click.MouseLeave:Connect(function()
		Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
		Tween(chev, { ImageColor3 = NullUI.Theme.TextDim, Position = UDim2.new(1, -16, 0.5, 0) }, 0.15)
	end)
	click.MouseButton1Click:Connect(function()
		Tween(card, { BackgroundTransparency = 0.8 }, 0.08)
		Tween(chev, { ImageColor3 = NullUI.Theme.Accent }, 0.08)
		task.delay(0.08, function()
			if not card.Parent then return end
			Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { ImageColor3 = NullUI.Theme.Text }, 0.15)
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)

	return {
		Instance = card,
		Destroy = function() card:Destroy() end,
	}
end

function Tab:AddCard(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local hasImage = (opts.Image and opts.Image ~= "") or opts.UserId ~= nil
	local hasButton = opts.ButtonText ~= nil and opts.ButtonText ~= ""
	local BUTTON_H, BUTTON_GAP, BUTTON_MARGIN = 32, 6, 4
	local buttonReserve = hasButton and (BUTTON_GAP + BUTTON_H + BUTTON_MARGIN) or 0

	local hasRating = type(opts.Rating) == "table"
	local RATING_LABEL_H, RATING_STAR_H, RATING_INPUT_H = 14, 20, 26
	local RATING_ROW_GAP, RATING_TOP_GAP, RATING_BOTTOM_MARGIN = 6, 10, 8
	local ratingHasTitle = hasRating and opts.Rating.Title and opts.Rating.Title ~= ""
	local ratingBlockH = 0
	if hasRating then
		local bodyH = (ratingHasTitle and (RATING_LABEL_H + RATING_ROW_GAP) or 0)
			+ RATING_STAR_H + RATING_ROW_GAP + RATING_INPUT_H
		ratingBlockH = RATING_TOP_GAP + bodyH + RATING_BOTTOM_MARGIN
	end

	local extraBottom = buttonReserve + ratingBlockH
	local topHeight = hasDesc and 56 or 44
	local height = topHeight + extraBottom
	local imgSize, imgPad = 34, 10

	local card = BaseCard(self._page, height)
	local textX = 14

	if hasImage then
		local imgHolder = Instance.new("Frame")
		imgHolder.Name = "Image"
		imgHolder.AnchorPoint = Vector2.new(0, 0.5)
		imgHolder.Position = UDim2.fromOffset(10, topHeight / 2)
		imgHolder.Size = UDim2.fromOffset(imgSize, imgSize)
		imgHolder.BackgroundTransparency = 1
		imgHolder.BorderSizePixel = 0
		imgHolder.ClipsDescendants = true
		imgHolder.ZIndex = Z.Content + 1
		imgHolder.Parent = card
		Corner(imgHolder, NullUI.Theme.CornerRadiusSm)
		Stroke(imgHolder, Color3.new(1, 1, 1), 1, 0.85)

		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Crop
		img.Size = UDim2.fromScale(1, 1)
		img.ZIndex = Z.Content + 2
		img.Parent = imgHolder
		Corner(img, NullUI.Theme.CornerRadiusSm)

		if opts.UserId then
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					opts.UserId,
					opts.ThumbnailType or Enum.ThumbnailType.HeadShot,
					opts.ThumbnailSize or Enum.ThumbnailSize.Size100x100
				)
				if ok and content and img.Parent then
					img.Image = content
				end
			end)
		else
			img.Image = ResolveIcon(opts.Image)
		end

		textX = 10 + imgSize + imgPad
	end

	local rightReserve = opts.Callback and 44 or 14
	AddTitleDesc(card, textX, rightReserve, opts.Title or "Card", opts.Description, topHeight, extraBottom)
	self._window:_RegisterSearchable(self, opts.Title or "Card", card)

	if opts.Callback then
		local chev = Instance.new("ImageLabel")
		chev.BackgroundTransparency = 1
		chev.Image = ResolveIcon("chevron-right")
		BindTheme(chev, "ImageColor3", "TextDim")
		chev.Size = UDim2.fromOffset(14, 14)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -16, 0.5, 0)
		chev.ZIndex = Z.Content + 1
		chev.Parent = card

		local click = Instance.new("TextButton")
		click.Text = ""
		click.AutoButtonColor = false
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = Z.Content + 3
		click.Parent = card

		click.MouseEnter:Connect(function()
			Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { ImageColor3 = NullUI.Theme.Text, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
		end)
		click.MouseLeave:Connect(function()
			Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
			Tween(chev, { ImageColor3 = NullUI.Theme.TextDim, Position = UDim2.new(1, -16, 0.5, 0) }, 0.15)
		end)
		click.MouseButton1Click:Connect(function()
			Tween(card, { BackgroundTransparency = 0.8 }, 0.08)
			task.delay(0.08, function()
				if card.Parent then Tween(card, { BackgroundTransparency = 0.9 }, 0.15) end
			end)
			task.spawn(opts.Callback)
		end)
	end

	if hasButton then
		local footerBtn = Instance.new("TextButton")
		footerBtn.Name = "FooterButton"
		footerBtn.Text = ""
		footerBtn.AutoButtonColor = false
		footerBtn.BackgroundColor3 = Color3.new(1, 1, 1)
		footerBtn.BackgroundTransparency = 0.85
		footerBtn.BorderSizePixel = 0
		footerBtn.Position = UDim2.new(0, 10, 1, -(BUTTON_H + BUTTON_MARGIN))
		footerBtn.Size = UDim2.new(1, -20, 0, BUTTON_H)
		footerBtn.ZIndex = Z.Content + 1
		footerBtn.Parent = card
		Corner(footerBtn, 8)
		local footerStroke = Stroke(footerBtn, Color3.new(1, 1, 1), 1, 0.85)

		local footerLabel = Instance.new("TextLabel")
		footerLabel.BackgroundTransparency = 1
		footerLabel.FontFace = NullUI.Theme.Font
		footerLabel.Text = opts.ButtonText
		BindTheme(footerLabel, "TextColor3", "Text")
		footerLabel.TextSize = 13
		footerLabel.Size = UDim2.fromScale(1, 1)
		footerLabel.ZIndex = Z.Content + 2
		footerLabel.Parent = footerBtn

		footerBtn.MouseEnter:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.7 }, 0.12)
			Tween(footerStroke, { Transparency = 0.7 }, 0.12)
		end)
		footerBtn.MouseLeave:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.85 }, 0.12)
			Tween(footerStroke, { Transparency = 0.85 }, 0.12)
		end)
		footerBtn.MouseButton1Click:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.55 }, 0.08)
			task.delay(0.08, function()
				if footerBtn.Parent then Tween(footerBtn, { BackgroundTransparency = 0.7 }, 0.15) end
			end)
			if opts.ButtonCallback then task.spawn(opts.ButtonCallback) end
		end)
	end

	local ratingBar
	if hasRating then
		local ratingOpts = opts.Rating

		local ratingHolder = Instance.new("Frame")
		ratingHolder.Name = "Rating"
		ratingHolder.BackgroundTransparency = 1
		ratingHolder.Position = UDim2.new(0, 10, 1, -(ratingBlockH + buttonReserve))
		ratingHolder.Size = UDim2.new(1, -20, 0, ratingBlockH - RATING_BOTTOM_MARGIN)
		ratingHolder.ZIndex = Z.Content + 1
		ratingHolder.Parent = card

		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = Color3.new(1, 1, 1)
		divider.BackgroundTransparency = 0.94
		divider.BorderSizePixel = 0
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.ZIndex = Z.Content + 1
		divider.Parent = ratingHolder

		local ratingBody = Instance.new("Frame")
		ratingBody.BackgroundTransparency = 1
		ratingBody.Position = UDim2.new(0, 0, 0, RATING_TOP_GAP)
		ratingBody.Size = UDim2.new(1, 0, 1, -RATING_TOP_GAP)
		ratingBody.ZIndex = Z.Content + 1
		ratingBody.Parent = ratingHolder

		local ratingLayout = Instance.new("UIListLayout")
		ratingLayout.Padding = UDim.new(0, RATING_ROW_GAP)
		ratingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ratingLayout.Parent = ratingBody

		if ratingHasTitle then
			local ratingLabel = Instance.new("TextLabel")
			ratingLabel.BackgroundTransparency = 1
			ratingLabel.FontFace = NullUI.Theme.Font
			ratingLabel.Text = ratingOpts.Title
			BindTheme(ratingLabel, "TextColor3", "Text")
			ratingLabel.TextSize = 13
			ratingLabel.TextXAlignment = Enum.TextXAlignment.Left
			ratingLabel.Size = UDim2.new(1, 0, 0, RATING_LABEL_H)
			ratingLabel.LayoutOrder = 1
			ratingLabel.ZIndex = Z.Content + 1
			ratingLabel.Parent = ratingBody
		end

		local starBar = BuildStarRow(ratingBody, 2, math.max(1, ratingOpts.MaxStars or 5),
			ratingOpts.StarColor or Color3.fromRGB(255, 196, 64), RATING_STAR_H, ratingOpts.Default)
		local feedback = BuildFeedbackRow(ratingBody, 3, RATING_INPUT_H, ratingOpts.Placeholder, ratingOpts.ButtonIcon)

		local clearOnSubmit = ratingOpts.ClearOnSubmit ~= false
		feedback.SendBtn.MouseButton1Click:Connect(function()
			local sel = starBar.Get()
			if sel <= 0 then
				starBar.Nudge()
				return
			end
			if ratingOpts.Callback then task.spawn(ratingOpts.Callback, sel, feedback.Box.Text) end
			if ratingOpts.WebhookUrl then
				task.spawn(function()
					NullUI:SendFeedbackWebhook(ratingOpts.WebhookUrl, sel, feedback.Box.Text, ratingOpts.WebhookOptions)
				end)
			end
			if clearOnSubmit then
				feedback.Box.Text = ""
				starBar.Set(ratingOpts.Default or 0)
			end
		end)

		ratingBar = {
			Get = function() return starBar.Get(), feedback.Box.Text end,
			Set = function(newStars, newText)
				starBar.Set(newStars)
				if newText ~= nil then feedback.Box.Text = newText end
			end,
		}
	end

	return {
		Instance = card,
		Rating = ratingBar,
		Destroy = function() card:Destroy() end,
	}
end

local CHANGELOG_TYPES = {
	Added   = { Color = Color3.fromRGB(120, 210, 140), Icon = "plus" },
	Fixed   = { Color = Color3.fromRGB(120, 170, 255), Icon = "wrench" },
	Changed = { Color = Color3.fromRGB(255, 190, 90),  Icon = "refresh-cw" },
	Removed = { Color = Color3.fromRGB(230, 120, 120), Icon = "minus" },
}

function Tab:AddChangelogEntry(opts)
	opts = opts or {}
	local version = opts.Version or "Update"
	local date = opts.Date
	local changes = opts.Changes or {}

	local PAD = 12
	local HEADER_H = 18
	local ROW_H = 22
	local ROW_GAP = 2
	local height = PAD * 2 + HEADER_H + (#changes > 0 and 8 or 0)

	local card = BaseCard(self._page, height)
	card.AutomaticSize = Enum.AutomaticSize.Y
	self._window:_RegisterSearchable(self, version, card)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card

	local versionLabel = Instance.new("TextLabel")
	versionLabel.BackgroundTransparency = 1
	versionLabel.FontFace = NullUI.Theme.Font
	versionLabel.Text = version
	BindTheme(versionLabel, "TextColor3", "Text")
	versionLabel.TextSize = 14
	versionLabel.TextXAlignment = Enum.TextXAlignment.Left
	versionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	versionLabel.Size = UDim2.new(1, date and -90 or 0, 0, HEADER_H)
	versionLabel.ZIndex = Z.Content + 1
	versionLabel.Parent = card

	if date then
		local dateLabel = Instance.new("TextLabel")
		dateLabel.BackgroundTransparency = 1
		dateLabel.FontFace = NullUI.Theme.FontRegular
		dateLabel.Text = date
		BindTheme(dateLabel, "TextColor3", "TextDim")
		dateLabel.TextSize = 12
		dateLabel.TextXAlignment = Enum.TextXAlignment.Right
		dateLabel.AnchorPoint = Vector2.new(1, 0)
		dateLabel.Position = UDim2.new(1, 0, 0, 2)
		dateLabel.Size = UDim2.fromOffset(90, HEADER_H)
		dateLabel.ZIndex = Z.Content + 1
		dateLabel.Parent = card
	end

	local rowsHolder = Instance.new("Frame")
	rowsHolder.Name = "Rows"
	rowsHolder.BackgroundTransparency = 1
	rowsHolder.Position = UDim2.fromOffset(0, HEADER_H + 8)
	rowsHolder.Size = UDim2.new(1, 0, 0, 0)
	rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
	rowsHolder.ZIndex = Z.Content + 1
	rowsHolder.Parent = card

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, ROW_GAP)
	rowsLayout.Parent = rowsHolder

	for i, change in ipairs(changes) do
		local kind = CHANGELOG_TYPES[change.Type] and change.Type or "Changed"
		local meta = CHANGELOG_TYPES[kind]

		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = i * 2 - 1
		row.ZIndex = Z.Content + 1
		row.Parent = rowsHolder

		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = meta.Color
		pill.BackgroundTransparency = 0.85
		pill.BorderSizePixel = 0
		pill.AnchorPoint = Vector2.zero
		pill.Position = UDim2.fromOffset(0, 1)
		pill.Size = UDim2.fromOffset(66, 18)
		pill.ZIndex = Z.Content + 2
		pill.Parent = row
		Corner(pill, 5)

		local pillLayout = Instance.new("UIListLayout")
		pillLayout.FillDirection = Enum.FillDirection.Horizontal
		pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pillLayout.Padding = UDim.new(0, 3)
		pillLayout.Parent = pill

		local pillIcon = Instance.new("ImageLabel")
		pillIcon.BackgroundTransparency = 1
		pillIcon.Image = ResolveIcon(meta.Icon)
		pillIcon.ImageColor3 = meta.Color
		pillIcon.Size = UDim2.fromOffset(9, 9)
		pillIcon.LayoutOrder = 1
		pillIcon.ZIndex = Z.Content + 3
		pillIcon.Parent = pill

		local pillLabel = Instance.new("TextLabel")
		pillLabel.BackgroundTransparency = 1
		pillLabel.FontFace = NullUI.Theme.Font
		pillLabel.Text = string.upper(kind)
		pillLabel.TextColor3 = meta.Color
		pillLabel.TextSize = 9
		pillLabel.AutomaticSize = Enum.AutomaticSize.X
		pillLabel.Size = UDim2.fromOffset(0, 12)
		pillLabel.LayoutOrder = 2
		pillLabel.ZIndex = Z.Content + 3
		pillLabel.Parent = pill

		local changeLabel = Instance.new("TextLabel")
		changeLabel.BackgroundTransparency = 1
		changeLabel.FontFace = NullUI.Theme.FontRegular
		changeLabel.Text = tostring(change.Text or "")
		BindTheme(changeLabel, "TextColor3", "TextDim")
		changeLabel.TextSize = 12
		changeLabel.TextXAlignment = Enum.TextXAlignment.Left
		changeLabel.TextYAlignment = Enum.TextYAlignment.Top
		changeLabel.TextWrapped = true
		changeLabel.TextTruncate = Enum.TextTruncate.None
		changeLabel.AutomaticSize = Enum.AutomaticSize.Y
		changeLabel.Position = UDim2.fromOffset(76, 0)
		changeLabel.Size = UDim2.new(1, -76, 0, ROW_H)
		changeLabel.ZIndex = Z.Content + 2
		changeLabel.Parent = row

		local function alignChangelogRow()
			local isMultiline = changeLabel.TextBounds.Y > 18
			if isMultiline then
				pill.AnchorPoint = Vector2.zero
				pill.Position = UDim2.fromOffset(0, 1)
				changeLabel.TextYAlignment = Enum.TextYAlignment.Top
			else
				pill.AnchorPoint = Vector2.new(0, 0.5)
				pill.Position = UDim2.new(0, 0, 0.5, 0)
				changeLabel.TextYAlignment = Enum.TextYAlignment.Center
			end
		end
		changeLabel:GetPropertyChangedSignal("TextBounds"):Connect(alignChangelogRow)
		task.defer(alignChangelogRow)

		if i < #changes then
			local separator = Instance.new("Frame")
			separator.Name = "Separator" .. i
			separator.BackgroundColor3 = Color3.new(1, 1, 1)
			separator.BackgroundTransparency = 0.93
			separator.BorderSizePixel = 0
			separator.Size = UDim2.new(1, 0, 0, 1)
			separator.LayoutOrder = i * 2
			separator.ZIndex = Z.Content + 1
			separator.Parent = rowsHolder
		end
	end

	return { Instance = card, Destroy = function() card:Destroy() end }
end

function Tab:AddLoadoutGroup(opts)
	opts = opts or {}
	local title = opts.Title or "Loadout"
	local color = opts.Color or NullUI.Theme.Accent
	local icons = opts.Icons or {}
	local buttonText = opts.ButtonText or "Equip"

	local PAD = 12
	local HEADER_H = 16
	local ICON_SIZE = 44
	local ROW_GAP = 8
	local BUTTON_H = 30
	local GAP1, GAP2 = 8, 10
	local height = PAD * 2 + HEADER_H + GAP1 + ICON_SIZE + GAP2 + BUTTON_H

	local card = BaseCard(self._page, height)
	self._window:_RegisterSearchable(self, title, card)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = card

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 1, 0.5, 0)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = Z.Content + 2
	dot.Parent = header
	Corner(dot, 3)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = string.upper(title)
	BindTheme(titleLabel, "TextColor3", "TextDim")
	titleLabel.TextSize = 12
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Position = UDim2.fromOffset(15, 0)
	titleLabel.Size = UDim2.new(1, -15, 1, 0)
	titleLabel.ZIndex = Z.Content + 2
	titleLabel.Parent = header

	local iconsRow = Instance.new("Frame")
	iconsRow.Name = "Icons"
	iconsRow.BackgroundTransparency = 1
	iconsRow.Position = UDim2.fromOffset(0, HEADER_H + GAP1)
	iconsRow.Size = UDim2.new(1, 0, 0, ICON_SIZE)
	iconsRow.ZIndex = Z.Content + 1
	iconsRow.Parent = card

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = iconsRow

	for i, iconAsset in ipairs(icons) do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.BackgroundColor3 = Color3.new(1, 1, 1)
		slot.BackgroundTransparency = 0.95
		slot.BorderSizePixel = 0
		slot.ClipsDescendants = true
		slot.Size = UDim2.new(1 / 3, -ROW_GAP * 2 / 3, 1, 0)
		slot.LayoutOrder = i
		slot.ZIndex = Z.Content + 2
		slot.Parent = iconsRow
		Corner(slot, NullUI.Theme.CornerRadiusSm)
		Stroke(slot, Color3.new(1, 1, 1), 1, 0.94)

		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = ResolveIcon(iconAsset)
		img.ImageColor3 = color
		img.ScaleType = Enum.ScaleType.Fit
		img.Position = UDim2.fromOffset(8, 8)
		img.Size = UDim2.new(1, -16, 1, -16)
		img.ZIndex = Z.Content + 3
		img.Parent = slot
	end

	local btn = Instance.new("TextButton")
	btn.Name = "EquipButton"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 0.92
	btn.BorderSizePixel = 0
	btn.Position = UDim2.fromOffset(0, HEADER_H + GAP1 + ICON_SIZE + GAP2)
	btn.Size = UDim2.new(1, 0, 0, BUTTON_H)
	btn.ZIndex = Z.Content + 1
	btn.Parent = card
	Corner(btn, 8)

	local btnLabel = Instance.new("TextLabel")
	btnLabel.BackgroundTransparency = 1
	btnLabel.FontFace = NullUI.Theme.Font
	btnLabel.Text = buttonText
	BindTheme(btnLabel, "TextColor3", "Text")
	btnLabel.TextSize = 12
	btnLabel.Size = UDim2.fromScale(1, 1)
	btnLabel.ZIndex = Z.Content + 2
	btnLabel.Parent = btn

	btn.MouseEnter:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
	end)
	btn.MouseLeave:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.92 }, 0.12)
	end)
	btn.MouseButton1Click:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.7 }, 0.08)
		task.delay(0.08, function()
			if btn.Parent then Tween(btn, { BackgroundTransparency = 0.85 }, 0.15) end
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)

	return { Instance = card, Destroy = function() card:Destroy() end }
end

function Tab:AddInfoGrid(opts)
	opts = opts or {}
	local title = opts.Title or "Info"
	local hasDesc = opts.Description and opts.Description ~= ""
	local items = opts.Items or {}
	local color = opts.Color
	local columns = opts.Columns or 2

	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local CHIP_H = 38
	local GRID_GAP = 8
	local rows = math.ceil(#items / columns)
	local gridH = rows > 0 and (rows * CHIP_H + (rows - 1) * GRID_GAP) or 0
	local height = PAD * 2 + HEADER_H + (rows > 0 and (10 + gridH) or 0)

	local card = BaseCard(self._page, height)
	self._window:_RegisterSearchable(self, title, card)

	local leftInset = 0
	if color then
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.BackgroundColor3 = color
		accent.BorderSizePixel = 0
		accent.Size = UDim2.new(0, 3, 1, PAD * 2 - 16)
		accent.Position = UDim2.fromOffset(6 - (PAD + 6), 8 - PAD)
		accent.ZIndex = Z.Content + 1
		accent.Parent = card
		Corner(accent, 1.5)
		leftInset = 6
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD + leftInset)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(0, 0)
	titleLabel.Size = UDim2.new(1, 0, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card

	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = NullUI.Theme.FontRegular
		descLabel.Text = opts.Description
		BindTheme(descLabel, "TextColor3", "TextDim")
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(0, 18)
		descLabel.Size = UDim2.new(1, 0, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end

	local chipValues = {}

	if rows > 0 then
		local grid = Instance.new("Frame")
		grid.Name = "Grid"
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(0, HEADER_H + 10)
		grid.Size = UDim2.new(1, 0, 0, gridH)
		grid.ZIndex = Z.Content + 1
		grid.Parent = card

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
		gridLayout.FillDirectionMaxCells = columns
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid

		local function relayout()
			local w = grid.AbsoluteSize.X / GetUIScale()
			if w <= 0 then return end
			local cellW = (w - GRID_GAP * (columns - 1)) / columns
			gridLayout.CellSize = UDim2.fromOffset(cellW, CHIP_H)
		end
		BindWidthLayout(grid, relayout)
		task.defer(relayout)

		for i, item in ipairs(items) do
			local chip = Instance.new("Frame")
			chip.Name = "Chip" .. i
			chip.BackgroundColor3 = Color3.new(1, 1, 1)
			chip.BackgroundTransparency = 0.95
			chip.BorderSizePixel = 0
			chip.LayoutOrder = i
			chip.ZIndex = Z.Content + 2
			chip.Parent = grid
			Corner(chip, 6)

			local chipPad = Instance.new("UIPadding")
			chipPad.PaddingTop = UDim.new(0, 6)
			chipPad.PaddingLeft = UDim.new(0, 8)
			chipPad.PaddingRight = UDim.new(0, 8)
			chipPad.Parent = chip

			local labelLabel = Instance.new("TextLabel")
			labelLabel.BackgroundTransparency = 1
			labelLabel.FontFace = NullUI.Theme.Font
			labelLabel.Text = tostring(item.Label or "")
			BindTheme(labelLabel, "TextColor3", "Text")
			labelLabel.TextSize = 12
			labelLabel.TextXAlignment = Enum.TextXAlignment.Left
			labelLabel.TextTruncate = Enum.TextTruncate.AtEnd
			labelLabel.Size = UDim2.new(1, 0, 0, 15)
			labelLabel.ZIndex = Z.Content + 3
			labelLabel.Parent = chip

			local valueLabel = Instance.new("TextLabel")
			valueLabel.Name = "Value"
			valueLabel.BackgroundTransparency = 1
			valueLabel.FontFace = NullUI.Theme.FontRegular
			valueLabel.Text = tostring(item.Value or "")
			BindTheme(valueLabel, "TextColor3", "TextDim")
			valueLabel.TextSize = 11
			valueLabel.TextXAlignment = Enum.TextXAlignment.Left
			valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
			valueLabel.Position = UDim2.fromOffset(0, 15)
			valueLabel.Size = UDim2.new(1, 0, 0, 12)
			valueLabel.ZIndex = Z.Content + 3
			valueLabel.Parent = chip

			if item.Label then chipValues[item.Label] = valueLabel end
		end
	end

	return {
		Instance = card,
		SetValue = function(_, label, value)
			local lbl = chipValues[label]
			if lbl then lbl.Text = tostring(value) end
		end,
		Destroy = function() card:Destroy() end,
	}
end

function Tab:AddSystemInfoGrid(opts)
	opts = opts or {}
	local Stats = game:GetService("Stats")
	local LocalPlayer = Players.LocalPlayer

	local runCount = BumpRunCount()

	local grid = self:AddInfoGrid({
		Title       = opts.Title or "System Info",
		Description = opts.Description,
		Color       = opts.Color,
		Columns     = opts.Columns or 2,
		Items = {
			{ Label = "FPS",           Value = "--" },
			{ Label = "Ping",          Value = "-- ms" },
			{ Label = "Executor",      Value = GetExecutorName() },
			{ Label = "Executions",    Value = tostring(runCount) },
			{ Label = "Server Region", Value = "Unknown" },
			{ Label = "Time of Day",   Value = "--:--" },
		},
	})

	local frames = 0
	local lastFpsUpdate = os.clock()
	self._janitor:Add(RunService.Heartbeat:Connect(function()
		frames = frames + 1
		local now = os.clock()
		local elapsed = now - lastFpsUpdate
		if elapsed >= 1 then
			grid:SetValue("FPS", math.floor(frames / elapsed + 0.5))
			frames = 0
			lastFpsUpdate = now
		end
	end))

	local alive = true
	self._janitor:Add(function() alive = false end)

	task.spawn(function()
		while alive and grid.Instance.Parent do
			pcall(function()
				local ping = 0
				pcall(function()
					ping = math.clamp(Stats.Network.ServerStatsItem["Data Ping"]:GetValue(), 0, 9999)
				end)
				grid:SetValue("Ping", math.floor(ping) .. " ms")

				local h = tonumber(os.date("%H"))
				local m = tonumber(os.date("%M"))
				grid:SetValue("Time of Day", FormatClock(h * 60 + m))
			end)
			task.wait(1)
		end
	end)

	task.spawn(function()
		local ok, region = pcall(function()
			return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(LocalPlayer)
		end)
		if ok and region and alive then grid:SetValue("Server Region", region) end
	end)

	return grid
end

function Tab:AddActiveUsersGrid(opts)
	opts = opts or {}
	local service = opts.Service
	local interval = opts.Interval or 30

	local grid = self:AddInfoGrid({
		Title       = opts.Title or "Active Users",
		Description = opts.Description,
		Color       = opts.Color,
		Columns     = 1,
		Items = { { Label = "Active Now", Value = "--" } },
	})

	if not service then
		grid:SetValue("Active Now", "No Service configured")
		return grid
	end

	local alive = true
	self._janitor:Add(function() alive = false end)

	task.spawn(function()
		while alive and grid.Instance.Parent do
			service:Heartbeat()
			local count, err = service:GetActiveCount()
			if alive and grid.Instance.Parent then
				grid:SetValue("Active Now", count and tostring(count) or ("Error: " .. tostring(err)))
			end
			task.wait(interval)
		end
	end)

	return grid
end

function Tab:AddLeaderboard(opts)
	opts = opts or {}
	local jan = self._janitor
	local service = opts.Service
	local interval = opts.Interval or 30
	local limit = math.clamp(opts.Limit or 5, 1, 50)
	local title = opts.Title or "Leaderboard"
	local hasDesc = opts.Description and opts.Description ~= ""

	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local ROW_H, ROW_GAP = 44, 6
	local listY = PAD + HEADER_H + 12
	local listH = limit * ROW_H + (limit - 1) * ROW_GAP
	local totalHeight = listY + listH + PAD

	local container = Instance.new("Frame")
	container.Name = "Leaderboard"
	BindTheme(container, "BackgroundColor3", "Surface")
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, totalHeight)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, NullUI.Theme.CornerRadiusSm)
	Stroke(container, Color3.new(1, 1, 1), 1, 0.92)
	self._window:_RegisterSearchable(self, title, container)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, PAD)
	titleLabel.Size = UDim2.new(1, -PAD * 2 - 32, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = container

	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = NullUI.Theme.FontRegular
		descLabel.Text = opts.Description
		BindTheme(descLabel, "TextColor3", "TextDim")
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(PAD, PAD + 18)
		descLabel.Size = UDim2.new(1, -PAD * 2 - 32, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = container
	end

	local revealMe = opts.RevealByDefault == true

	local revealBtn = Instance.new("TextButton")
	revealBtn.Name = "RevealToggle"
	revealBtn.Text = ""
	revealBtn.AutoButtonColor = false
	revealBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	revealBtn.BackgroundTransparency = 1
	revealBtn.BorderSizePixel = 0
	revealBtn.AnchorPoint = Vector2.new(1, 0)
	revealBtn.Position = UDim2.new(1, -PAD, 0, PAD - 4)
	revealBtn.Size = UDim2.fromOffset(24, 24)
	revealBtn.ZIndex = Z.Content + 2
	revealBtn.Parent = container
	Corner(revealBtn, 7)

	local revealIcon = Instance.new("ImageLabel")
	revealIcon.BackgroundTransparency = 1
	revealIcon.Image = ResolveIcon(revealMe and "eye" or "eye-off")
	BindTheme(revealIcon, "ImageColor3", "TextDim")
	revealIcon.Size = UDim2.fromOffset(14, 14)
	revealIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	revealIcon.Position = UDim2.fromScale(0.5, 0.5)
	revealIcon.ZIndex = Z.Content + 3
	revealIcon.Parent = revealBtn

	jan:Add(revealBtn.MouseEnter:Connect(function()
		Tween(revealBtn, { BackgroundTransparency = 0.9 }, 0.12)
		Tween(revealIcon, { ImageColor3 = NullUI.Theme.Text }, 0.12)
	end))
	jan:Add(revealBtn.MouseLeave:Connect(function()
		Tween(revealBtn, { BackgroundTransparency = 1 }, 0.12)
		Tween(revealIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.12)
	end))

	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, PAD + HEADER_H + 8)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(PAD, listY)
	list.Size = UDim2.new(1, -PAD * 2, 0, listH)
	list.ZIndex = Z.Content + 1
	list.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, ROW_GAP)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = NullUI.Theme.FontRegular
	emptyLabel.Text = "No one's run this yet"
	BindTheme(emptyLabel, "TextColor3", "TextDim")
	emptyLabel.TextSize = 12
	emptyLabel.Position = UDim2.fromOffset(PAD, listY + 10)
	emptyLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	emptyLabel.Visible = false
	emptyLabel.ZIndex = Z.Content + 1
	emptyLabel.Parent = container

	local RANK_COLORS = {
		[1] = Color3.fromRGB(255, 196, 64),
		[2] = Color3.fromRGB(203, 209, 217),
		[3] = Color3.fromRGB(205, 141, 92),
	}
	local RANK_ICONS = { [1] = "crown", [2] = "medal", [3] = "medal" }

	local function formatSeconds(total)
		total = math.floor(total or 0)
		local h = math.floor(total / 3600)
		local m = math.floor((total % 3600) / 60)
		if h > 0 then return string.format("%dh %dm", h, m) end
		if m > 0 then return string.format("%dm", m) end
		return string.format("%ds", total)
	end

	local function fallbackLabel(identity)
		local tag = (identity or ""):gsub("-", ""):sub(1, 4):upper()
		return "Player-" .. (tag ~= "" and tag or "????")
	end

	local rowFrames = {}
	local function clearRows()
		for _, f in ipairs(rowFrames) do f:Destroy() end
		table.clear(rowFrames)
	end

	local function buildRow(index, item)
		local rankColor = RANK_COLORS[index]

		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.Active = true
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = item.IsYou and 0.9 or 0.96
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.ZIndex = Z.Content + 2
		row.Parent = list
		Corner(row, NullUI.Theme.CornerRadiusSm)
		Stroke(row, Color3.new(1, 1, 1), 1, item.IsYou and 0.88 or 0.94)

		local baseTransparency = row.BackgroundTransparency
		row.MouseEnter:Connect(function() Tween(row, { BackgroundTransparency = baseTransparency - 0.05 }, 0.12) end)
		row.MouseLeave:Connect(function() Tween(row, { BackgroundTransparency = baseTransparency }, 0.12) end)

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = row

		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 0, 0.5, 0)
		badge.Size = UDim2.fromOffset(28, 28)
		badge.BackgroundColor3 = Color3.new(1, 1, 1)
		badge.BackgroundTransparency = 0.94
		badge.BorderSizePixel = 0
		badge.ZIndex = Z.Content + 3
		badge.Parent = row
		Corner(badge, 14)
		Stroke(badge, Color3.new(1, 1, 1), 1, 0.9)

		if rankColor then
			local badgeIcon = Instance.new("ImageLabel")
			badgeIcon.BackgroundTransparency = 1
			badgeIcon.Image = ResolveIcon(RANK_ICONS[index])
			badgeIcon.ImageColor3 = rankColor
			badgeIcon.Size = UDim2.fromOffset(15, 15)
			badgeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			badgeIcon.Position = UDim2.fromScale(0.5, 0.5)
			badgeIcon.ZIndex = Z.Content + 4
			badgeIcon.Parent = badge
		else
			local badgeLabel = Instance.new("TextLabel")
			badgeLabel.BackgroundTransparency = 1
			badgeLabel.FontFace = NullUI.Theme.Font
			badgeLabel.Text = "#" .. tostring(index)
			BindTheme(badgeLabel, "TextColor3", "TextDim")
			badgeLabel.TextSize = 11
			badgeLabel.Size = UDim2.fromScale(1, 1)
			badgeLabel.ZIndex = Z.Content + 4
			badgeLabel.Parent = badge
		end

		local avatarHolder = Instance.new("Frame")
		avatarHolder.AnchorPoint = Vector2.new(0, 0.5)
		avatarHolder.Position = UDim2.new(0, 34, 0.5, 0)
		avatarHolder.Size = UDim2.fromOffset(28, 28)
		avatarHolder.BackgroundColor3 = Color3.new(1, 1, 1)
		avatarHolder.BackgroundTransparency = 0.94
		avatarHolder.BorderSizePixel = 0
		avatarHolder.ClipsDescendants = true
		avatarHolder.ZIndex = Z.Content + 3
		avatarHolder.Parent = row
		Corner(avatarHolder, 14)
		Stroke(avatarHolder, Color3.new(1, 1, 1), 1, 0.85)

		if item.UserId and item.UserId ~= 0 then
			local avatarImg = Instance.new("ImageLabel")
			avatarImg.BackgroundTransparency = 1
			avatarImg.ScaleType = Enum.ScaleType.Crop
			avatarImg.Size = UDim2.fromScale(1, 1)
			avatarImg.ZIndex = Z.Content + 4
			avatarImg.Parent = avatarHolder
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					item.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
				if ok and content and avatarImg.Parent then
					avatarImg.Image = content
				end
			end)
		else
			local placeholder = Instance.new("ImageLabel")
			placeholder.BackgroundTransparency = 1
			placeholder.Image = ResolveIcon("user")
			BindTheme(placeholder, "ImageColor3", "TextDim")
			placeholder.Size = UDim2.fromOffset(14, 14)
			placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
			placeholder.Position = UDim2.fromScale(0.5, 0.5)
			placeholder.ZIndex = Z.Content + 4
			placeholder.Parent = avatarHolder
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.FontFace = NullUI.Theme.Font
		nameLabel.Text = (item.NamePreview and item.NamePreview ~= "" and item.NamePreview or fallbackLabel(item.Identity))
			.. (item.IsYou and "  (You)" or "")
		BindTheme(nameLabel, "TextColor3", "Text")
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Position = UDim2.fromOffset(70, 0)
		nameLabel.Size = UDim2.new(1, -70 - 68, 1, 0)
		nameLabel.ZIndex = Z.Content + 3
		nameLabel.Parent = row

		local timeLabel = Instance.new("TextLabel")
		timeLabel.BackgroundTransparency = 1
		timeLabel.FontFace = NullUI.Theme.FontRegular
		timeLabel.Text = formatSeconds(item.Seconds)
		BindTheme(timeLabel, "TextColor3", "TextDim")
		timeLabel.TextSize = 12
		timeLabel.TextXAlignment = Enum.TextXAlignment.Right
		timeLabel.AnchorPoint = Vector2.new(1, 0)
		timeLabel.Position = UDim2.new(1, 0, 0, 0)
		timeLabel.Size = UDim2.fromOffset(60, ROW_H)
		timeLabel.ZIndex = Z.Content + 3
		timeLabel.Parent = row

		return row
	end

	local function renderRows(items)
		clearRows()
		emptyLabel.Visible = #items == 0

		for i, item in ipairs(items) do
			if i > limit then break end
			table.insert(rowFrames, buildRow(i, item))
		end
	end

	renderRows({})

	if not service then
		return { Instance = container }
	end

	local function maskName(letters, stars)
		local name = LocalPlayer.Name or ""
		return name:sub(1, letters) .. stars
	end

	jan:Add(revealBtn.MouseButton1Click:Connect(function()
		revealMe = not revealMe
		revealIcon.Image = ResolveIcon(revealMe and "eye" or "eye-off")
		NullUI:Notify({
			Title = "Leaderboard",
			Text  = revealMe
				and "Your avatar and more of your name will show on the leaderboard."
				or "Back to anonymous -- only 2 letters of your name will show.",
			Type  = "info",
			Duration = 3,
		})
	end))

	local alive = true
	jan:Add(function() alive = false end)

	task.spawn(function()
		while alive and container.Parent do
			local payload = revealMe
				and { UserId = LocalPlayer.UserId, NamePreview = maskName(4, "*******") }
				or { UserId = 0, NamePreview = maskName(2, "********") }
			service:Heartbeat(payload)

			local items, err = service:GetLeaderboard(limit)
			if alive and container.Parent and items then
				for _, item in ipairs(items) do
					item.IsYou = item.Identity == service.Identity
				end
				renderRows(items)
			end
			task.wait(interval)
		end
	end)

	return { Instance = container }
end

function Tab:AddGradientCard(opts)
	opts = opts or {}
	local title = opts.Title or "Card"
	local hasDesc = opts.Description and opts.Description ~= ""
	local colorA = opts.ColorA or Color3.fromRGB(88, 101, 242)
	local colorB = opts.ColorB or Color3.fromRGB(52, 58, 138)
	local height = hasDesc and 56 or 44

	local card = Instance.new("Frame")
	card.Name = title .. "GradientCard"
	card.BackgroundColor3 = colorA
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, height)
	card.ZIndex = Z.Content
	card.Parent = self._page
	Corner(card, NullUI.Theme.CornerRadiusSm)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(colorA, colorB)
	gradient.Rotation = 100
	gradient.Parent = card

	self._window:_RegisterSearchable(self, title, card)

	local PAD = 14
	local rightReserve = opts.Callback and 32 or PAD

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, hasDesc and 9 or 0)
	titleLabel.Size = UDim2.new(1, -(PAD + rightReserve), 0, 18)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card

	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = NullUI.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = Color3.new(1, 1, 1)
		descLabel.TextTransparency = 0.3
		descLabel.TextSize = 12
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextTruncate = Enum.TextTruncate.AtEnd
		descLabel.Position = UDim2.fromOffset(PAD, 29)
		descLabel.Size = UDim2.new(1, -(PAD + rightReserve), 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end

	if opts.Callback then
		local chev = Instance.new("ImageLabel")
		chev.BackgroundTransparency = 1
		chev.Image = ResolveIcon("chevron-right")
		chev.ImageColor3 = Color3.new(1, 1, 1)
		chev.ImageTransparency = 0.2
		chev.Size = UDim2.fromOffset(14, 14)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -14, 0.5, 0)
		chev.ZIndex = Z.Content + 1
		chev.Parent = card

		local veil = Instance.new("Frame")
		veil.Name = "HoverVeil"
		veil.BackgroundColor3 = Color3.new(1, 1, 1)
		veil.BackgroundTransparency = 1
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = Z.Content + 2
		veil.Parent = card
		Corner(veil, NullUI.Theme.CornerRadiusSm)

		local click = Instance.new("TextButton")
		click.Text = ""
		click.AutoButtonColor = false
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = Z.Content + 3
		click.Parent = card

		click.MouseEnter:Connect(function()
			Tween(veil, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { Position = UDim2.new(1, -10, 0.5, 0) }, 0.15)
		end)
		click.MouseLeave:Connect(function()
			Tween(veil, { BackgroundTransparency = 1 }, 0.15)
			Tween(chev, { Position = UDim2.new(1, -14, 0.5, 0) }, 0.15)
		end)
		click.MouseButton1Click:Connect(function()
			Tween(veil, { BackgroundTransparency = 0.8 }, 0.08)
			task.delay(0.08, function()
				if veil.Parent then Tween(veil, { BackgroundTransparency = 0.9 }, 0.15) end
			end)
			task.spawn(opts.Callback)
		end)
	end

	return { Instance = card, Destroy = function() card:Destroy() end }
end

function Tab:AddToggle(opts)
	opts = opts or {}
	local state = opts.Default == true
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)

	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 66, opts.Text or "Toggle", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Toggle", card)

	local switchBg = Instance.new("Frame")
	switchBg.AnchorPoint = Vector2.new(1, 0.5)
	switchBg.Position = UDim2.new(1, -14, 0.5, 0)
	switchBg.Size = UDim2.fromOffset(40, 22)
	switchBg.BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(46, 50, 49)
	switchBg.BackgroundTransparency = state and 0 or 0.32
	switchBg.BorderSizePixel = 0
	switchBg.ZIndex = Z.Content + 1
	switchBg.Parent = card
	Corner(switchBg, 11)

	-- The disabled state stays translucent so the window background remains visible
	-- through the control instead of turning into a flat gray pill.
	local switchStroke = Stroke(
		switchBg,
		state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(205, 212, 209),
		1,
		state and 0.88 or 0.72
	)

	local switchGradient = Instance.new("UIGradient")
	switchGradient.Rotation = 90
	switchGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 198, 194)),
	})
	switchGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, state and 0 or 0.76),
		NumberSequenceKeypoint.new(1, state and 0 or 0.94),
	})
	switchGradient.Parent = switchBg

	local switchScale = Instance.new("UIScale")
	switchScale.Scale = 1
	switchScale.Parent = switchBg

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.BackgroundColor3 = state and Color3.fromRGB(18, 18, 18) or Color3.fromRGB(226, 230, 228)
	knob.BackgroundTransparency = state and 0 or 0.06
	knob.BorderSizePixel = 0
	knob.ZIndex = Z.Content + 2
	knob.Parent = switchBg
	Corner(knob, 8)

	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card

	local function render()
		local anim = 0.28
		local style, dir = Enum.EasingStyle.Quint, Enum.EasingDirection.InOut
		Tween(switchBg, {
			BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(46, 50, 49),
			BackgroundTransparency = state and 0 or 0.32,
		}, anim, style, dir)
		Tween(switchStroke, {
			Color = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(205, 212, 209),
			Transparency = state and 0.88 or 0.72,
		}, anim, style, dir)
		switchGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, state and 0 or 0.76),
			NumberSequenceKeypoint.new(1, state and 0 or 0.94),
		})
		Tween(knob, {
			BackgroundColor3 = state and Color3.fromRGB(18, 18, 18) or Color3.fromRGB(226, 230, 228),
			BackgroundTransparency = state and 0 or 0.06,
			Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}, anim, style, dir)
	end

	local signal = MakeSignal()
	local function fireChanged(newState)
		if opts.Callback then task.spawn(opts.Callback, newState) end
		signal.Fire(newState)
	end

	local locked = opts.Locked == true
	click.MouseButton1Click:Connect(function()
		if locked then return end
		Tween(switchScale, { Scale = 0.91 }, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.08, function()
			if switchScale.Parent then
				Tween(switchScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end)
		state = not state
		render()
		fireChanged(state)
	end)

	card.MouseEnter:Connect(function()
		if not locked then
			Tween(card, { BackgroundTransparency = 0.93 }, 0.15)
			if not state then
				Tween(switchStroke, { Transparency = 0.55 }, 0.15)
				Tween(switchBg, { BackgroundTransparency = 0.24 }, 0.15)
			end
		end
	end)
	card.MouseLeave:Connect(function()
		Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
		if not state then
			Tween(switchStroke, { Transparency = 0.72 }, 0.15)
			Tween(switchBg, { BackgroundTransparency = 0.32 }, 0.15)
		end
	end)

	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, value, silent)
			state = value == true
			render()
			if not silent then fireChanged(state) end
		end,
		Get = function() return state end,
		SetLocked = function(_, v)
			locked = v == true
			card.BackgroundTransparency = locked and 0.98 or 0.96
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() signal.Clear(); card:Destroy() end,
	}, "Toggle")
end

local ActiveSliderOwner = nil

function Tab:AddSlider(opts)
	opts = opts or {}
	local min = tonumber(opts.Min) or 0
	local max = tonumber(opts.Max) or 100
	if max < min then min, max = max, min end
	local increment = tonumber(opts.Increment) or 1
	local value = math.clamp(tonumber(opts.Default) or min, min, max)

	local hasDesc = opts.Description and opts.Description ~= ""
	local jan = self._janitor

	local card = BaseCard(self._page, hasDesc and 76 or 56)
	local textX = AddLeadingIcon(card, opts.Icon, 24)
	local leadingIcon = card:FindFirstChild("LeadingIcon")
	if leadingIcon then
		leadingIcon.AnchorPoint = Vector2.new(0, 0)
		leadingIcon.Position = UDim2.fromOffset(14, 9)
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = NullUI.Theme.Font
	label.Text = opts.Text or "Slider"
	BindTheme(label, "TextColor3", "Text")
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(textX, 8)
	label.Size = UDim2.new(1, -(textX + 76), 0, 18)
	label.ZIndex = Z.Content + 1
	label.Parent = card
	self._window:_RegisterSearchable(self, opts.Text or "Slider", card)

	local descLabel
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = NullUI.Theme.FontRegular
		descLabel.Text = opts.Description
		BindTheme(descLabel, "TextColor3", "TextDim")
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.Position = UDim2.fromOffset(textX, 26)
		descLabel.Size = UDim2.new(1, -(textX + 14), 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = NullUI.Theme.FontRegular
	valueLabel.Text = FormatNumber(value) .. (opts.Suffix or "")
	BindTheme(valueLabel, "TextColor3", "TextDim")
	valueLabel.TextSize = 13
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -14, 0, 8)
	valueLabel.Size = UDim2.fromOffset(62, 18)
	valueLabel.ZIndex = Z.Content + 1
	valueLabel.Parent = card

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 14, 1, -20)
	track.Size = UDim2.new(1, -28, 0, 6)
	-- Nearly transparent white overlay: no gray tint, so the window background
	-- remains visible through the unfilled portion of the slider.
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.BackgroundTransparency = 0.91
	track.BorderSizePixel = 0
	track.ZIndex = Z.Content + 1
	track.Parent = card
	Corner(track, 3)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(SafeAlpha(value, min, max), 0, 1, 0)
	fill.ZIndex = Z.Content + 2
	fill.Parent = track
	Corner(fill, 3)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(SafeAlpha(value, min, max), 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0
	knob.BorderSizePixel = 0
	knob.ZIndex = Z.Content + 3
	knob.Parent = track
	Corner(knob, 6)
	Stroke(knob, Color3.fromRGB(16, 16, 16), 2, 0)

	if hasDesc then
		local lastW = -1
		local function relayout()
			local w = card.AbsoluteSize.X / GetUIScale()
			if w <= 0 or math.abs(w - lastW) < 1 then return end
			lastW = w
			local _, h = MeasureText(opts.Description, 12, math.max(w - textX - 14, 40))
			card.Size = UDim2.new(1, 0, 0, math.max(76, 26 + h + 8 + 20))
		end
		BindWidthLayout(card, relayout)
		task.defer(relayout)
	end

	local function setVisual(alpha, animated, duration)
		if animated then
			Tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, duration or 0.16)
			Tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, duration or 0.16)
		else
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		end
	end

	local targetAlpha = SafeAlpha(value, min, max)
	local visualAlpha = targetAlpha

	local signal = MakeSignal()
	local function fireChanged(v)
		if opts.Callback then task.spawn(opts.Callback, v) end
		signal.Fire(v)
	end

	local function setValueLabel()
		valueLabel.Text = FormatNumber(value) .. (opts.Suffix or "")
	end

	local function moveTo(newValue, animated)
		value = math.clamp(newValue, min, max)
		local alpha = SafeAlpha(value, min, max)
		targetAlpha = alpha
		visualAlpha = alpha
		setValueLabel()
		setVisual(alpha, animated ~= false, 0.18)
	end

	local dragging = false
	local sliderInput = nil
	local sliderOwner = {}
	local followConn = nil

	local function updateFromX(xPos)
		if track.AbsoluteSize.X <= 0 then return end
		targetAlpha = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = min + targetAlpha * (max - min)
		local newValue = SnapToIncrement(raw, min, max, increment)
		if newValue ~= value then
			value = newValue
			setValueLabel()
			fireChanged(value)
		end
	end

	local SLIDER_SMOOTH = 22

	local function stopFollow()
		if followConn then
			followConn:Disconnect()
			followConn = nil
		end
	end

	local function releaseSlider()
		if ActiveSliderOwner == sliderOwner then ActiveSliderOwner = nil end
		dragging = false
		sliderInput = nil
		stopFollow()
	end
	jan:Add(releaseSlider)
	jan:Add(card.Destroying:Connect(releaseSlider))
	jan:Add(UserInputService.WindowFocusReleased:Connect(releaseSlider))

	local hitBox = Instance.new("TextButton")
	hitBox.Name = "SliderHitBox"
	hitBox.Text = ""
	hitBox.AutoButtonColor = false
	hitBox.BackgroundTransparency = 1
	hitBox.AnchorPoint = Vector2.new(0.5, 0.5)
	hitBox.Position = UDim2.fromScale(0.5, 0.5)
	hitBox.Size = UDim2.new(1, 8, 0, 26)
	hitBox.ZIndex = Z.Content + 4
	hitBox.Parent = track

	jan:Add(hitBox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging or ActiveSliderOwner ~= nil then return end
		ActiveSliderOwner = sliderOwner
		dragging = true
		sliderInput = input
		updateFromX(input.Position.X)

		stopFollow()
		followConn = RunService.RenderStepped:Connect(function(dt)
			if not track.Parent then stopFollow() return end
			local a = 1 - math.exp(-SLIDER_SMOOTH * dt)
			visualAlpha = visualAlpha + (targetAlpha - visualAlpha) * a
			if math.abs(targetAlpha - visualAlpha) < 0.001 then
				visualAlpha = targetAlpha
			end
			setVisual(visualAlpha, false)
		end)
		jan:Add(followConn)
	end))

	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging or ActiveSliderOwner ~= sliderOwner then return end
		if input == sliderInput
			or (sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement) then
			updateFromX(input.Position.X)
		end
	end))

	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if not dragging or ActiveSliderOwner ~= sliderOwner then return end
		if input ~= sliderInput
			and not (sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			return
		end
		releaseSlider()
		targetAlpha = SafeAlpha(value, min, max)
		visualAlpha = targetAlpha
		setVisual(targetAlpha, true, 0.12)
	end))

	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			moveTo(SnapToIncrement(tonumber(v) or min, min, max, increment), true)
			if not silent then fireChanged(value) end
		end,
		Get = function() return value end,
		SetRange = function(_, newMin, newMax)
			min, max = newMin, newMax
			moveTo(math.clamp(value, min, max), true)
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() stopFollow(); signal.Clear(); card:Destroy() end,
	}, "Slider")
end

local function ComputePopupPosition(window, card, w, h)
	local s = GetUIScale()
	local realW, realH = w * s, h * s

	local view = ViewportSize()
	local winPos = window.AbsolutePosition
	local winSize = window.AbsoluteSize
	local cardPos = card.AbsolutePosition

	local px = winPos.X + winSize.X + 12
	if px + realW > view.X - 8 then
		px = winPos.X - realW - 12
	end
	px = SafeClamp(px, 8, view.X - realW - 8)

	local py = cardPos.Y - realH - 8
	py = SafeClamp(py, winPos.Y + 8, winPos.Y + winSize.Y - realH - 8)
	py = SafeClamp(py, 8, view.Y - realH - 8)

	return math.round(px / s), math.round(py / s)
end

local function FollowPopup(window, card, width, height, getPopup)
	return ObserveProperties({
		{window, "AbsolutePosition", "AbsoluteSize"},
		{card, "AbsolutePosition", "AbsoluteSize"},
		{NullUI._Root, "AbsoluteSize"},
		{GlobalScale, "Scale"},
	}, function()
		local popup = getPopup()
		if not popup or not popup.Parent or not card.Parent then return end
		local x, y = ComputePopupPosition(window, card, width, height)
		popup.Position = UDim2.fromOffset(x, y)
	end)
end

function Tab:AddDropdown(opts)
	opts = opts or {}
	local options = opts.Options or {}
	local isMulti = opts.MultiSelect == true
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor

	local selected
	if isMulti then
		selected = {}
		if type(opts.Default) == "table" then
			for _, v in ipairs(opts.Default) do selected[v] = true end
		end
	else
		selected = opts.Default or options[1]
	end

	local signal = MakeSignal()
	local function fireChanged(newValue)
		if opts.Callback then task.spawn(opts.Callback, newValue) end
		signal.Fire(newValue)
	end

	local function getSelectedList()
		local list = {}
		for _, name in ipairs(options) do
			if isMulti and selected[name] then table.insert(list, name) end
		end
		return list
	end

	local function isOptionSelected(name)
		if isMulti then return selected[name] == true end
		return name == selected
	end

	local function formatValue()
		if isMulti then
			local list = getSelectedList()
			if #list == 0 then return "None" end
			if #list == 1 then return list[1] end
			return #list .. " selected"
		end
		return tostring(selected or "None")
	end

	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)

	AddTitleDesc(card, textX, 166, opts.Text or "Dropdown", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Dropdown", card)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = NullUI.Theme.FontRegular
	valueLabel.Text = formatValue()
	BindTheme(valueLabel, "TextColor3", "TextDim")
	valueLabel.TextSize = 13
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, -34, 0.5, 0)
	valueLabel.Size = UDim2.fromOffset(120, height)
	valueLabel.ZIndex = Z.Content + 1
	valueLabel.Parent = card

	local chevron = Instance.new("ImageLabel")
	chevron.BackgroundTransparency = 1
	chevron.Image = ResolveIcon("chevron-down")
	BindTheme(chevron, "ImageColor3", "TextDim")
	chevron.Size = UDim2.fromOffset(14, 14)
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -14, 0.5, 0)
	chevron.ZIndex = Z.Content + 1
	chevron.Parent = card

	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card

	local popupOpen = false
	local popupFrame, popupBackdrop, followConn, scrollConn
	local optionButtons = {}

	local function closePopup()
		if not popupOpen then return end
		popupOpen = false
		RegisterPopupClose(closePopup)
		Tween(chevron, { Rotation = 0 }, 0.15)

		if followConn then followConn:Disconnect(); followConn = nil end
		if scrollConn then scrollConn:Disconnect(); scrollConn = nil end
		table.clear(optionButtons)

		if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end

		if popupFrame then
			local pf = popupFrame
			popupFrame = nil
			Tween(pf, { Size = UDim2.new(0, pf.Size.X.Offset, 0, 0) }, 0.4,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(pf, { BackgroundTransparency = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.4, function() if pf then pf:Destroy() end end)
		end
	end

	local function refreshOptionVisual(name)
		local entry = optionButtons[name]
		if not entry then return end
		local sel = isOptionSelected(name)
		Tween(entry.button, { BackgroundTransparency = sel and 0.9 or 1 }, 0.1)
		Tween(entry.label, { TextColor3 = sel and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.1)
		if entry.check then
			Tween(entry.check, { BackgroundTransparency = sel and 0.05 or 0.9 }, 0.1)
		end
		if entry.checkIcon then
			Tween(entry.checkIcon, { ImageTransparency = sel and 0 or 1 }, 0.1)
		end
	end

	local function openPopup()
		if popupOpen then return end
		popupOpen = true
		RegisterPopupOpen(closePopup)
		Tween(chevron, { Rotation = 180 }, 0.15)

		local root = NullUI._Root
		local mainWindow = self._window and self._window._gui or root

		local rowH, padV = 30, 12
		local contentH = #options * rowH + math.max(#options - 1, 0) * 2 + padV
		local targetHeight = math.min(contentH, 220, math.max(1, (ViewportSize().Y - 16) / GetUIScale()))

		local popupW = 140
		for _, name in ipairs(options) do
			local w = MeasureText(tostring(name), 13, 1000)
			popupW = math.max(popupW, w + 66)
		end
		popupW = math.min(popupW, ViewportSize().X / GetUIScale() - 24)

		popupBackdrop = MakePopupBackdrop(closePopup)

		popupFrame = Instance.new("Frame")
		popupFrame.ClipsDescendants = true
		popupFrame.Name = "DropdownPopup"
		popupFrame.Active = true
		BindTheme(popupFrame, "BackgroundColor3", "Background")
		popupFrame.BackgroundTransparency = 1
		popupFrame.BorderSizePixel = 0
		popupFrame.ZIndex = Z.Popup
		popupFrame.Size = UDim2.new(0, popupW, 0, 0)
		popupFrame.Parent = root
		Corner(popupFrame, 10)
		local popupStroke = Stroke(popupFrame, Color3.new(1, 1, 1), 1, 0.92)
		GlassLayer(popupFrame, 10, 0.985)

		local px, py = ComputePopupPosition(mainWindow, card, popupW, targetHeight)
		popupFrame.Position = UDim2.fromOffset(px, py)

		local optionsHolder = Instance.new("ScrollingFrame")
		optionsHolder.Name = "Options"
		optionsHolder.BackgroundTransparency = 1
		optionsHolder.BorderSizePixel = 0
		optionsHolder.Size = UDim2.fromScale(1, 1)
		optionsHolder.ScrollingDirection = Enum.ScrollingDirection.Y
		optionsHolder.ScrollBarThickness = 0
		optionsHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
		optionsHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
		optionsHolder.ZIndex = Z.Popup + 1
		optionsHolder.Parent = popupFrame

		local optPad = Instance.new("UIPadding")
		optPad.PaddingTop = UDim.new(0, 6)
		optPad.PaddingBottom = UDim.new(0, 6)
		optPad.PaddingLeft = UDim.new(0, 6)
		optPad.PaddingRight = UDim.new(0, 16)
		optPad.Parent = optionsHolder

		local optLayout = Instance.new("UIListLayout")
		optLayout.Padding = UDim.new(0, 2)
		optLayout.SortOrder = Enum.SortOrder.LayoutOrder
		optLayout.Parent = optionsHolder

		AddScrollbar(optionsHolder)
		AddContentScrollThumb(optionsHolder, optLayout, popupFrame, {
			Add = function(_, conn) scrollConn = conn end,
		})

		for i, optionName in ipairs(options) do
			local optBtn = Instance.new("TextButton")
			optBtn.Text = ""
			optBtn.AutoButtonColor = false
			optBtn.BackgroundColor3 = Color3.new(1, 1, 1)
			optBtn.BackgroundTransparency = isOptionSelected(optionName) and 0.9 or 1
			optBtn.BorderSizePixel = 0
			optBtn.Size = UDim2.new(1, 0, 0, rowH)
			optBtn.LayoutOrder = i
			optBtn.ZIndex = Z.Popup + 2
			optBtn.Parent = optionsHolder
			Corner(optBtn, 8)

			local optLabel = Instance.new("TextLabel")
			optLabel.BackgroundTransparency = 1
			optLabel.FontFace = NullUI.Theme.FontRegular
			optLabel.Text = tostring(optionName)
			optLabel.TextColor3 = isOptionSelected(optionName) and NullUI.Theme.Text or NullUI.Theme.TextDim
			optLabel.TextSize = 13
			optLabel.TextXAlignment = Enum.TextXAlignment.Left
			optLabel.TextTruncate = Enum.TextTruncate.AtEnd
			optLabel.Position = UDim2.fromOffset(10, 0)
			optLabel.Size = UDim2.new(1, -34, 1, 0)
			optLabel.ZIndex = Z.Popup + 3
			optLabel.Parent = optBtn

			local entry = { button = optBtn, label = optLabel }

			if isMulti then
				local check = Instance.new("Frame")
				check.Name = "Check"
				check.AnchorPoint = Vector2.new(1, 0.5)
				check.Position = UDim2.new(1, -10, 0.5, 0)
				check.Size = UDim2.fromOffset(14, 14)
				check.BackgroundColor3 = Color3.new(1, 1, 1)
				check.BackgroundTransparency = isOptionSelected(optionName) and 0.05 or 0.9
				check.BorderSizePixel = 0
				check.ZIndex = Z.Popup + 3
				check.Parent = optBtn
				Corner(check, 4)
				Stroke(check, Color3.new(1, 1, 1), 1, 0.75)

				local checkIcon = Instance.new("ImageLabel")
				checkIcon.Name = "Icon"
				checkIcon.BackgroundTransparency = 1
				checkIcon.Image = ResolveIcon("check")
				BindTheme(checkIcon, "ImageColor3", "Background")
				checkIcon.ImageTransparency = isOptionSelected(optionName) and 0 or 1
				checkIcon.Size = UDim2.fromOffset(10, 10)
				checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
				checkIcon.Position = UDim2.fromScale(0.5, 0.5)
				checkIcon.ZIndex = Z.Popup + 4
				checkIcon.Parent = check

				entry.check = check
				entry.checkIcon = checkIcon
			elseif isOptionSelected(optionName) then
				local check = Instance.new("ImageLabel")
				check.Name = "SingleCheck"
				check.BackgroundTransparency = 1
				check.Image = ResolveIcon("check")
				BindTheme(check, "ImageColor3", "Text")
				check.Size = UDim2.fromOffset(14, 14)
				check.AnchorPoint = Vector2.new(1, 0.5)
				check.Position = UDim2.new(1, -10, 0.5, 0)
				check.ZIndex = Z.Popup + 3
				check.Parent = optBtn
			end

			optionButtons[optionName] = entry

			optBtn.MouseEnter:Connect(function()
				if not isOptionSelected(optionName) then
					Tween(optBtn, { BackgroundTransparency = 0.85 }, 0.1)
				end
			end)
			optBtn.MouseLeave:Connect(function()
				if not isOptionSelected(optionName) then
					Tween(optBtn, { BackgroundTransparency = 1 }, 0.1)
				end
			end)

			optBtn.MouseButton1Click:Connect(function()
				if isMulti then
					selected[optionName] = (not selected[optionName]) or nil
					refreshOptionVisual(optionName)
					valueLabel.Text = formatValue()
					fireChanged(getSelectedList())
				else
					selected = optionName
					valueLabel.Text = formatValue()
					fireChanged(optionName)
					closePopup()
				end
			end)
		end

		Tween(popupFrame, {
			Size = UDim2.new(0, popupW, 0, targetHeight),
			BackgroundTransparency = 0.15,
		}, 0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(popupStroke, { Transparency = 0.85 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

		followConn = FollowPopup(mainWindow, card, popupW, targetHeight, function() return popupFrame end)
		jan:Add(followConn)
	end

	click.MouseButton1Click:Connect(function()
		if popupOpen then closePopup() else openPopup() end
	end)

	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)

	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			if isMulti then
				selected = {}
				if type(v) == "table" then
					for _, name in ipairs(v) do selected[name] = true end
				end
			else
				selected = v
			end
			valueLabel.Text = formatValue()
			for name in pairs(optionButtons) do refreshOptionVisual(name) end
			if not silent then
				fireChanged(isMulti and getSelectedList() or selected)
			end
		end,
		Get = function()
			if isMulti then return getSelectedList() end
			return selected
		end,
		SetOptions = function(_, newOptions)
			options = newOptions or {}
			closePopup()
			valueLabel.Text = formatValue()
		end,
		Refresh = function(_, newOptions)
			options = newOptions or options
			closePopup()
			valueLabel.Text = formatValue()
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() closePopup(); signal.Clear(); card:Destroy() end,
	}, "Dropdown")
end

function Tab:AddTextbox(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)

	local textX = AddLeadingIcon(card, opts.Icon, height)

	local iconGap, rightPad, pillMinW = 29, 12, 90
	local titleReserve = pillMinW + 26

	local _, _, refreshTextLayout = AddTitleDesc(card, textX, function() return titleReserve end, opts.Text or "Textbox", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Textbox", card)

	local pill, pillStroke = CreateInputPill(card, pillMinW)

	local penIcon = Instance.new("ImageLabel")
	penIcon.BackgroundTransparency = 1
	penIcon.Image = ResolveIcon("pencil")
	BindTheme(penIcon, "ImageColor3", "TextDim")
	penIcon.Size = UDim2.fromOffset(13, 13)
	penIcon.AnchorPoint = Vector2.new(0, 0.5)
	penIcon.Position = UDim2.new(0, 10, 0.5, 0)
	penIcon.ZIndex = Z.Content + 3
	penIcon.Parent = pill

	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.FontFace = NullUI.Theme.FontRegular
	box.PlaceholderText = opts.Placeholder or ""
	box.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
	box.Text = opts.Default or ""
	BindTheme(box, "TextColor3", "Text")
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ClipsDescendants = true
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(iconGap, 0)
	box.Size = UDim2.new(1, -(iconGap + 10), 1, 0)
	box.ZIndex = Z.Content + 3
	box.Parent = pill

	local currentPillW = pillMinW

	local function resizePill(animated)
		local sample = box.Text ~= "" and box.Text or box.PlaceholderText
		local textW = MeasureText(sample, 13, 2000)
		local desiredW = iconGap + textW + rightPad

		local realCardW = card.AbsoluteSize.X > 0 and card.AbsoluteSize.X or 400
		local cardW = realCardW / GetUIScale()
		local maxW = math.max(pillMinW, math.floor(cardW * 0.5))
		local targetW = math.clamp(desiredW, pillMinW, maxW)

		if math.abs(targetW - currentPillW) < 1 then return end
		currentPillW = targetW
		titleReserve = targetW + 26
		refreshTextLayout()

		if animated == false then
			pill.Size = UDim2.fromOffset(targetW, 26)
		else
			Tween(pill, { Size = UDim2.fromOffset(targetW, 26) }, 0.16,
				Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end

	box:GetPropertyChangedSignal("Text"):Connect(function() resizePill(true) end)
	BindWidthLayout(card, function() resizePill(false) end)
	task.defer(function() resizePill(false) end)

	box.Focused:Connect(function()
		Tween(pillStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.82 }, 0.15)
	end)

	local signal = MakeSignal()
	local function fireChanged(text, enterPressed)
		if opts.Callback then task.spawn(opts.Callback, text, enterPressed) end
		signal.Fire(text, enterPressed)
	end

	box.FocusLost:Connect(function(enterPressed)
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.9 }, 0.15)
		fireChanged(box.Text, enterPressed)
	end)

	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			box.Text = tostring(v or "")
			resizePill()
			if not silent then fireChanged(box.Text, false) end
		end,
		Get = function() return box.Text end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() signal.Clear(); card:Destroy() end,
	}, "Textbox")
end

local function MiniField(parent, label, width, zBase)
	zBase = zBase or Z.Popup

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(width, 36)
	holder.ZIndex = zBase + 1
	holder.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = NullUI.Theme.FontRegular
	lbl.Text = label
	BindTheme(lbl, "TextColor3", "TextDim")
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, 0, 0, 12)
	lbl.ZIndex = zBase + 2
	lbl.Parent = holder

	local field = Instance.new("Frame")
	field.Position = UDim2.fromOffset(0, 12)
	field.Size = UDim2.new(1, 0, 0, 24)
	field.BackgroundColor3 = Color3.new(1, 1, 1)
	field.BackgroundTransparency = 0.92
	field.BorderSizePixel = 0
	field.ZIndex = zBase + 2
	field.Parent = holder
	Corner(field, 7)
	local fieldStroke = Stroke(field, Color3.new(1, 1, 1), 1, 0.88)

	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.FontFace = NullUI.Theme.FontRegular
	box.Text = ""
	BindTheme(box, "TextColor3", "Text")
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = zBase + 3
	box.Parent = field

	box.Focused:Connect(function()
		Tween(fieldStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(field, { BackgroundTransparency = 0.84 }, 0.15)
	end)
	box.FocusLost:Connect(function()
		Tween(fieldStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		Tween(field, { BackgroundTransparency = 0.92 }, 0.15)
	end)

	return holder, box
end

function Tab:AddColorPicker(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor

	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 52, opts.Text or "Color", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Color", card)

	local color = opts.Default or Color3.fromRGB(255, 255, 255)
	local hue, sat, val = Color3.toHSV(color)

	local swatchHolder = Instance.new("Frame")
	swatchHolder.AnchorPoint = Vector2.new(1, 0.5)
	swatchHolder.Position = UDim2.new(1, -14, 0.5, 0)
	swatchHolder.Size = UDim2.fromOffset(24, 24)
	swatchHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	swatchHolder.BackgroundTransparency = 0.9
	swatchHolder.BorderSizePixel = 0
	swatchHolder.ZIndex = Z.Content + 1
	swatchHolder.Parent = card
	Corner(swatchHolder, 6)
	local swatchStroke = Stroke(swatchHolder, Color3.new(1, 1, 1), 1, 0.85)

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.fromScale(0.5, 0.5)
	swatch.Size = UDim2.fromOffset(16, 16)
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.ZIndex = Z.Content + 2
	swatch.Parent = swatchHolder
	Corner(swatch, 4)

	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card

	local popupOpen = false
	local popupFrame, popupBackdrop, followConn
	local svCursor, hueCursor, svBox, hueBar, satGradient
	local hexBox, rBox, gBox, bBox
	local originalHue, originalSat, originalVal
	local draggingSV, draggingHue = false, false
	local colorInput = nil
	local dragEndedAt = 0

	local function currentColor()
		return Color3.fromHSV(hue, sat, val)
	end

	local function syncFields()
		if svCursor then svCursor.Position = UDim2.new(sat, 0, 1 - val, 0) end
		if hueCursor then hueCursor.Position = UDim2.new(0.5, 0, hue, 0) end
		if svBox then svBox.BackgroundColor3 = Color3.new(1, 1, 1) end
		if satGradient then
			satGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		end

		local c = currentColor()
		local r = math.floor(c.R * 255 + 0.5)
		local g = math.floor(c.G * 255 + 0.5)
		local b = math.floor(c.B * 255 + 0.5)
		if hexBox and not hexBox:IsFocused() then hexBox.Text = "#" .. c:ToHex():upper() end
		if rBox and not rBox:IsFocused() then rBox.Text = tostring(r) end
		if gBox and not gBox:IsFocused() then gBox.Text = tostring(g) end
		if bBox and not bBox:IsFocused() then bBox.Text = tostring(b) end
	end

	local signal = MakeSignal()
	local lastFired = nil

	local function ColorsClose(a, b)
		if a == nil or b == nil then return false end
		return math.abs(a.R - b.R) < 0.001
			and math.abs(a.G - b.G) < 0.001
			and math.abs(a.B - b.B) < 0.001
	end

	local function applyColor(fireCallback)
		local c = currentColor()
		swatch.BackgroundColor3 = c
		syncFields()
		if fireCallback then
			if not ColorsClose(c, lastFired) then
				lastFired = c
				if opts.Callback then task.spawn(opts.Callback, c) end
				signal.Fire(c)
			end
		end
	end

	local function closePopup()
		if not popupOpen then return end
		popupOpen = false
		draggingSV, draggingHue = false, false
		colorInput = nil
		RegisterPopupClose(closePopup)
		Tween(swatchStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.85 }, 0.15)

		if followConn then followConn:Disconnect(); followConn = nil end
		if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end

		if popupFrame then
			local pf = popupFrame
			popupFrame = nil
			svCursor, hueCursor, svBox, hueBar, satGradient = nil, nil, nil, nil, nil
			hexBox, rBox, gBox, bBox = nil, nil, nil, nil
			Tween(pf, { Size = UDim2.new(0, pf.Size.X.Offset, 0, 0) }, 0.4,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(pf, { BackgroundTransparency = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.4, function() if pf then pf:Destroy() end end)
		end
	end

	local function updateSV(inputPos)
		if not svBox or svBox.AbsoluteSize.X <= 0 then return end
		local rel, sz = svBox.AbsolutePosition, svBox.AbsoluteSize
		sat = math.clamp((inputPos.X - rel.X) / sz.X, 0, 1)
		val = 1 - math.clamp((inputPos.Y - rel.Y) / sz.Y, 0, 1)
		applyColor(true)
	end

	local function updateHue(inputPos)
		if not hueBar or hueBar.AbsoluteSize.X <= 0 then return end
		local rel, sz = hueBar.AbsolutePosition, hueBar.AbsoluteSize
		hue = math.clamp((inputPos.Y - rel.Y) / sz.Y, 0, 1)
		applyColor(true)
	end

	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not popupFrame then return end
		if input ~= colorInput
			and not (colorInput and colorInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement) then
			return
		end
		if draggingSV then updateSV(input.Position) end
		if draggingHue then updateHue(input.Position) end
	end))

	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if input == colorInput
			or (colorInput and colorInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			if draggingSV or draggingHue then
				dragEndedAt = os.clock()
			end
			draggingSV, draggingHue = false, false
			colorInput = nil
		end
	end))

	local function requestCloseFromBackdrop()
		if draggingSV or draggingHue then return end
		if os.clock() - dragEndedAt < 0.2 then return end
		closePopup()
	end

	local function openPopup()
		if popupOpen then return end
		popupOpen = true
		originalHue, originalSat, originalVal = hue, sat, val
		lastFired = currentColor()
		RegisterPopupOpen(closePopup)
		Tween(swatchStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)

		local root = NullUI._Root
		local mainWindow = self._window and self._window._gui or root
		local popupW, popupH = 400, 306

		popupBackdrop = MakePopupBackdrop(requestCloseFromBackdrop)

		popupFrame = Instance.new("ScrollingFrame")
		popupFrame.CanvasSize = UDim2.fromOffset(0, 0)
		popupFrame.ScrollingEnabled = false
		popupFrame.ScrollingDirection = Enum.ScrollingDirection.Y
		popupFrame.ScrollBarThickness = 3
		BindTheme(popupFrame, "ScrollBarImageColor3", "TextDim")
		popupFrame.ScrollBarImageTransparency = 0.35
		popupFrame.BorderSizePixel = 0
		popupFrame.Name = "ColorPickerPopup"
		popupFrame.Active = true
		BindTheme(popupFrame, "BackgroundColor3", "Background")
		popupFrame.BackgroundTransparency = 0
		popupFrame.BorderSizePixel = 0
		popupFrame.ClipsDescendants = true
		popupFrame.ZIndex = Z.Popup
		popupFrame.Size = UDim2.new(0, popupW, 0, 0)
		popupFrame.Parent = root
		Corner(popupFrame, 10)
		local popupStroke = Stroke(popupFrame, Color3.new(1, 1, 1), 1, 0.92)
		GlassLayer(popupFrame, 10, 0.985)

		popupFrame.AnchorPoint = Vector2.new(0.5, 0.5)
  local fit = Instance.new("UIScale")
  fit.Parent = popupFrame
  local function centerPicker()
   if not popupFrame then return end
   local scale = GetUIScale()
   local view = ViewportSize()
   fit.Scale = math.min(1, math.max(0.1, (view.X - 24) / (popupW * scale)), math.max(0.1, (view.Y - 24) / (popupH * scale)))
   local pos, size = mainWindow.AbsolutePosition, mainWindow.AbsoluteSize
   local halfW, halfH = popupW * scale * fit.Scale / 2, popupH * scale * fit.Scale / 2
   local x = math.clamp(pos.X + size.X / 2, halfW + 12, math.max(halfW + 12, view.X - halfW - 12))
   local y = math.clamp(pos.Y + size.Y / 2, halfH + 12, math.max(halfH + 12, view.Y - halfH - 12))
   popupFrame.Position = UDim2.fromOffset(x / scale, y / scale)
  end
  centerPicker()

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 14)
		pad.PaddingBottom = UDim.new(0, 14)
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = popupFrame

		local innerW = popupW - 28
  local heading = Instance.new("TextLabel")
  heading.BackgroundTransparency = 1
  heading.Text = opts.Text or "Colorpicker"
  heading.FontFace = NullUI.Theme.Font
  heading.TextSize = 17
  heading.TextXAlignment = Enum.TextXAlignment.Left
  heading.Size = UDim2.new(1, 0, 0, 24)
  heading.ZIndex = Z.Popup + 2
  BindTheme(heading, "TextColor3", "Text")
  heading.Parent = popupFrame

		svBox = Instance.new("Frame")
		svBox.Active = true
		svBox.Position = UDim2.fromOffset(0, 38)
		svBox.Size = UDim2.fromOffset(190, 178)
		svBox.BackgroundColor3 = Color3.new(1, 1, 1)
		svBox.BorderSizePixel = 0
		svBox.ClipsDescendants = true
		svBox.ZIndex = Z.Popup + 1
		svBox.Parent = popupFrame
		Corner(svBox, 8)

		satGradient = Instance.new("UIGradient")
		satGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		satGradient.Parent = svBox

		local valOverlay = Instance.new("Frame")
		valOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		valOverlay.BorderSizePixel = 0
		valOverlay.Size = UDim2.fromScale(1, 1)
		valOverlay.ZIndex = Z.Popup + 1
		valOverlay.Parent = svBox
		local valGradient = Instance.new("UIGradient")
		valGradient.Rotation = 90
		valGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		valGradient.Parent = valOverlay

		local svCursorLayer = Instance.new("Frame")
		svCursorLayer.BackgroundTransparency = 1
		svCursorLayer.BorderSizePixel = 0
		svCursorLayer.ClipsDescendants = false
		svCursorLayer.Position = svBox.Position
		svCursorLayer.Size = svBox.Size
		svCursorLayer.ZIndex = Z.Popup + 2
		svCursorLayer.Parent = popupFrame

		svCursor = Instance.new("Frame")
		svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		svCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
		svCursor.Size = UDim2.fromOffset(16, 16)
		svCursor.BackgroundTransparency = 1
		svCursor.ZIndex = Z.Popup + 3
		svCursor.Parent = svCursorLayer
		Corner(svCursor, 8)
		Stroke(svCursor, Color3.new(0, 0, 0), 2, 0.15)

		local svCursorInner = Instance.new("Frame")
		svCursorInner.AnchorPoint = Vector2.new(0.5, 0.5)
		svCursorInner.Position = UDim2.fromScale(0.5, 0.5)
		svCursorInner.Size = UDim2.fromOffset(11, 11)
		svCursorInner.BackgroundTransparency = 1
		svCursorInner.ZIndex = Z.Popup + 4
		svCursorInner.Parent = svCursor
		Corner(svCursorInner, 6)
		Stroke(svCursorInner, Color3.new(1, 1, 1), 2, 0)

		hueBar = Instance.new("Frame")
		hueBar.Active = true
		hueBar.Position = UDim2.fromOffset(202, 38)
		hueBar.Size = UDim2.fromOffset(12, 178)
		hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
		hueBar.BorderSizePixel = 0
		hueBar.ClipsDescendants = true
		hueBar.ZIndex = Z.Popup + 1
		hueBar.Parent = popupFrame
		Corner(hueBar, 5)

		local hueGradient = Instance.new("UIGradient")
		hueGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.000, Color3.fromHSV(0.000, 1, 1)),
			ColorSequenceKeypoint.new(0.166, Color3.fromHSV(0.166, 1, 1)),
			ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
			ColorSequenceKeypoint.new(0.500, Color3.fromHSV(0.500, 1, 1)),
			ColorSequenceKeypoint.new(0.666, Color3.fromHSV(0.666, 1, 1)),
			ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
			ColorSequenceKeypoint.new(1.000, Color3.fromHSV(1.000, 1, 1)),
		})
		hueGradient.Rotation = 90
		hueGradient.Parent = hueBar

		local hueCursorLayer = Instance.new("Frame")
		hueCursorLayer.BackgroundTransparency = 1
		hueCursorLayer.BorderSizePixel = 0
		hueCursorLayer.ClipsDescendants = false
		hueCursorLayer.Position = hueBar.Position
		hueCursorLayer.Size = hueBar.Size
		hueCursorLayer.ZIndex = Z.Popup + 2
		hueCursorLayer.Parent = popupFrame

		hueCursor = Instance.new("Frame")
		hueCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		hueCursor.Position = UDim2.new(0.5, 0, hue, 0)
		hueCursor.Size = UDim2.fromOffset(12, 6)
		hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
		hueCursor.BorderSizePixel = 0
		hueCursor.ZIndex = Z.Popup + 3
		hueCursor.Parent = hueCursorLayer
		Corner(hueCursor, 3)
		Stroke(hueCursor, Color3.new(0, 0, 0), 1, 0.4)

		local hexHolder, hexRef = MiniField(popupFrame, "HEX", 140, Z.Popup)
		hexHolder.Position = UDim2.fromOffset(230, 34)
		hexBox = hexRef

		local rgbRow = Instance.new("Frame")
		rgbRow.BackgroundTransparency = 1
		rgbRow.Position = UDim2.fromOffset(230, 80)
		rgbRow.Size = UDim2.fromOffset(140, 136)
		rgbRow.ZIndex = Z.Popup + 1
		rgbRow.Parent = popupFrame

		local rHolder, rRef = MiniField(rgbRow, "Red", 140, Z.Popup)
		rHolder.Position = UDim2.fromOffset(0, 0)
		rBox = rRef

		local gHolder, gRef = MiniField(rgbRow, "Green", 140, Z.Popup)
		gHolder.Position = UDim2.fromOffset(0, 46)
		gBox = gRef

		local bHolder, bRef = MiniField(rgbRow, "Blue", 140, Z.Popup)
		bHolder.Position = UDim2.fromOffset(0, 92)
		bBox = bRef

		local btnRow = Instance.new("Frame")
		btnRow.BackgroundTransparency = 1
		btnRow.Position = UDim2.fromOffset(0, 246)
		btnRow.Size = UDim2.fromOffset(innerW, 30)
		btnRow.ZIndex = Z.Popup + 1
		btnRow.Parent = popupFrame

		local function MakeButton(text, x, w, filled)
			local btn = Instance.new("TextButton")
			btn.Position = UDim2.fromOffset(x, 0)
			btn.Size = UDim2.fromOffset(w, 30)
			btn.FontFace = NullUI.Theme.Font
			btn.Text = text
			btn.TextSize = 13
			btn.AutoButtonColor = false
			btn.BorderSizePixel = 0
			btn.ZIndex = Z.Popup + 2
			if filled then
				BindTheme(btn, "BackgroundColor3", "Accent")
				btn.BackgroundTransparency = 0
				BindTheme(btn, "TextColor3", "Background")
			else
				btn.BackgroundColor3 = Color3.new(1, 1, 1)
				btn.BackgroundTransparency = 0.92
				BindTheme(btn, "TextColor3", "Text")
			end
			btn.Parent = btnRow
			Corner(btn, 8)
			if not filled then Stroke(btn, Color3.new(1, 1, 1), 1, 0.88) end
			return btn
		end

		local halfW = (innerW - 10) / 2
		local cancelBtn = MakeButton("Cancel", 0, halfW, false)
		local doneBtn   = MakeButton("Done", halfW + 10, halfW, true)

		cancelBtn.Activated:Connect(function()
			hue, sat, val = originalHue, originalSat, originalVal
			applyColor(true)
			closePopup()
		end)
		doneBtn.Activated:Connect(closePopup)

		svBox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingSV or draggingHue then return end
				draggingSV = true
				colorInput = input
				updateSV(input.Position)
			end
		end)

		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingSV or draggingHue then return end
				draggingHue = true
				colorInput = input
				updateHue(input.Position)
			end
		end)

		hexBox:GetPropertyChangedSignal("Text"):Connect(function()
			local filtered = hexBox.Text:gsub("[^%x]", "")
			filtered = filtered:sub(1, 6)
			if filtered ~= hexBox.Text then hexBox.Text = filtered end
		end)

		hexBox.FocusLost:Connect(function()
			local clean = hexBox.Text:gsub("#", "")
			if #clean == 3 then
				clean = clean:sub(1, 1):rep(2) .. clean:sub(2, 2):rep(2) .. clean:sub(3, 3):rep(2)
			end
			if #clean == 6 then
				local ok, c = pcall(Color3.fromHex, clean)
				if ok and c then
					hue, sat, val = Color3.toHSV(c)
					applyColor(true)
					return
				end
			end
			syncFields()
		end)

		local function filterDigits(b)
			b:GetPropertyChangedSignal("Text"):Connect(function()
				local filtered = b.Text:gsub("%D", ""):sub(1, 3)
				if filtered ~= b.Text then b.Text = filtered end
			end)
		end
		filterDigits(rBox); filterDigits(gBox); filterDigits(bBox)

		local function onRGBCommit()
			local r = math.clamp(tonumber(rBox.Text) or 0, 0, 255)
			local g = math.clamp(tonumber(gBox.Text) or 0, 0, 255)
			local b = math.clamp(tonumber(bBox.Text) or 0, 0, 255)
			hue, sat, val = Color3.toHSV(Color3.fromRGB(r, g, b))
			applyColor(true)
		end
		rBox.FocusLost:Connect(onRGBCommit)
		gBox.FocusLost:Connect(onRGBCommit)
		bBox.FocusLost:Connect(onRGBCommit)

		syncFields()

		Tween(popupFrame, {
			Size = UDim2.new(0, popupW, 0, popupH),
			BackgroundTransparency = 0,
		}, 0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(popupStroke, { Transparency = 0.85 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

		followConn = RunService.RenderStepped:Connect(centerPicker)
		jan:Add(followConn)
	end

	click.MouseButton1Click:Connect(function()
		if popupOpen then closePopup() else openPopup() end
	end)

	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)

	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, c, silent)
			hue, sat, val = Color3.toHSV(c)
			applyColor(not silent)
			if silent then lastFired = currentColor() end
		end,
		Get = function() return currentColor() end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() closePopup(); signal.Clear(); card:Destroy() end,
	}, "ColorPicker")
end

function Tab:AddKeybind(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor

	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 128, opts.Text or "Keybind", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Keybind", card)

	local currentKey = opts.Default

	local pill, pillStroke = CreateInputPill(card, 104)

	local keyIcon = Instance.new("ImageLabel")
	keyIcon.BackgroundTransparency = 1
	keyIcon.Image = ResolveIcon("keyboard")
	BindTheme(keyIcon, "ImageColor3", "TextDim")
	keyIcon.Size = UDim2.fromOffset(13, 13)
	keyIcon.AnchorPoint = Vector2.new(0, 0.5)
	keyIcon.Position = UDim2.new(0, 10, 0.5, 0)
	keyIcon.ZIndex = Z.Content + 3
	keyIcon.Parent = pill

	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundTransparency = 1
	keyLabel.FontFace = NullUI.Theme.FontRegular
	keyLabel.Text = currentKey and currentKey.Name or "None"
	BindTheme(keyLabel, "TextColor3", "Text")
	keyLabel.TextSize = 13
	keyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	keyLabel.TextXAlignment = Enum.TextXAlignment.Left
	keyLabel.Position = UDim2.fromOffset(29, 0)
	keyLabel.Size = UDim2.new(1, -37, 1, 0)
	keyLabel.ZIndex = Z.Content + 3
	keyLabel.Parent = pill

	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 4
	click.Parent = pill

	local listening = false
	local listenConn = nil
	local signal = MakeSignal()

	local function fireChanged(key)
		signal.Fire(key)
	end

	local function stopListening()
		listening = false
		KeybindCapturing = false
		if listenConn then listenConn:Disconnect(); listenConn = nil end
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.9 }, 0.15)
		keyLabel.Text = currentKey and currentKey.Name or "None"
	end

	local function startListening()
		if listening then return end
		listening = true
		KeybindCapturing = true
		keyLabel.Text = "..."
		Tween(pillStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.82 }, 0.15)

		listenConn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

			if input.KeyCode == Enum.KeyCode.Escape then
				stopListening()
				return
			end
			if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				currentKey = nil
				stopListening()
				fireChanged(nil)
				return
			end

			currentKey = input.KeyCode
			stopListening()
			if opts.Callback then task.spawn(opts.Callback, currentKey, "bind") end
			fireChanged(currentKey)
		end)
		jan:Add(listenConn)
	end

	click.MouseButton1Click:Connect(startListening)

	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if listening or KeybindCapturing or gameProcessed then return end
		if UserInputService:GetFocusedTextBox() then return end
		if currentKey
			and input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == currentKey then
			if opts.Callback then task.spawn(opts.Callback, currentKey, "press") end
		end
	end))

	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)

	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, key, silent)
			currentKey = key
			keyLabel.Text = key and key.Name or "None"
			if not silent then fireChanged(key) end
		end,
		Get = function() return currentKey end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() stopListening(); signal.Clear(); card:Destroy() end,
	}, "Keybind")
end

local ConsoleColors = {
	[Enum.MessageType.MessageInfo]    = Color3.fromRGB(120, 170, 255),
	[Enum.MessageType.MessageWarning] = Color3.fromRGB(255, 190, 90),
	[Enum.MessageType.MessageError]   = Color3.fromRGB(255, 105, 105),
	[Enum.MessageType.MessageOutput]  = nil,
}

function Tab:AddConsole(opts)
	opts = opts or {}
	local height = opts.Height or 200
	local maxLogs = opts.MaxLogs or 300
	local jan = self._janitor

	local container = Instance.new("Frame")
	container.Name = "Console"
	BindTheme(container, "BackgroundColor3", "Surface")
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, height)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, NullUI.Theme.CornerRadiusSm)
	Stroke(container, Color3.new(1, 1, 1), 1, 0.92)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 34)
	header.ZIndex = Z.Content + 1
	header.Parent = container

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 12)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header

	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -70, 1, 0)
	titleRow.ZIndex = Z.Content + 2
	titleRow.Parent = header

	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow

	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon("terminal")
	BindTheme(titleIcon, "ImageColor3", "TextDim")
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = Z.Content + 3
	titleIcon.Parent = titleRow

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = opts.Title or "Debug Console"
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 13
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Content + 3
	titleLabel.Parent = titleRow

	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(58, 24)
	controls.ZIndex = Z.Content + 2
	controls.Parent = header

	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls

	local function iconButton(icon, order)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(24, 24)
		btn.LayoutOrder = order
		btn.ZIndex = Z.Content + 3
		btn.Parent = controls
		Corner(btn, 7)

		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		BindTheme(ic, "ImageColor3", "TextDim")
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = Z.Content + 4
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

	local copyBtn, copyIcon = iconButton("copy", 1)
	local clearBtn = iconButton("trash-2", 2)

	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.fromOffset(0, 34)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container

	local logsScroll = Instance.new("ScrollingFrame")
	logsScroll.Name = "Logs"
	logsScroll.BackgroundTransparency = 1
	logsScroll.BorderSizePixel = 0
	logsScroll.Position = UDim2.fromOffset(0, 35)
	logsScroll.Size = UDim2.new(1, 0, 1, -35)
	logsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	logsScroll.ScrollBarThickness = 0
	logsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	logsScroll.ZIndex = Z.Content + 1
	logsScroll.Parent = container

	local logsPad = Instance.new("UIPadding")
	logsPad.PaddingTop = UDim.new(0, 8)
	logsPad.PaddingBottom = UDim.new(0, 8)
	logsPad.PaddingLeft = UDim.new(0, 10)
	logsPad.PaddingRight = UDim.new(0, 10)
	logsPad.Parent = logsScroll

	local logsLayout = Instance.new("UIListLayout")
	logsLayout.Padding = UDim.new(0, 4)
	logsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logsLayout.Parent = logsScroll

	AddScrollbar(logsScroll)
	AddContentScrollThumb(logsScroll, logsLayout, container, jan)

	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Position = UDim2.fromOffset(0, 35)
	emptyState.Size = UDim2.new(1, 0, 1, -35)
	emptyState.ZIndex = Z.Content + 2
	emptyState.Parent = container

	local emptyLayout = Instance.new("UIListLayout")
	emptyLayout.FillDirection = Enum.FillDirection.Vertical
	emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emptyLayout.Padding = UDim.new(0, 6)
	emptyLayout.Parent = emptyState

	local emptyIcon = Instance.new("ImageLabel")
	emptyIcon.BackgroundTransparency = 1
	emptyIcon.Image = ResolveIcon("frown")
	BindTheme(emptyIcon, "ImageColor3", "TextDim")
	emptyIcon.Size = UDim2.fromOffset(22, 22)
	emptyIcon.LayoutOrder = 1
	emptyIcon.ZIndex = Z.Content + 3
	emptyIcon.Parent = emptyState

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = NullUI.Theme.FontRegular
	emptyLabel.Text = "No logs at the moment"
	BindTheme(emptyLabel, "TextColor3", "TextDim")
	emptyLabel.TextSize = 12
	emptyLabel.AutomaticSize = Enum.AutomaticSize.XY
	emptyLabel.Size = UDim2.fromOffset(0, 14)
	emptyLabel.LayoutOrder = 2
	emptyLabel.ZIndex = Z.Content + 3
	emptyLabel.Parent = emptyState

	local logs = {}
	local logCount = 0
	local counter = 0
	local autoScroll = true

	local function trimLogs()
		while logCount > maxLogs do
			local oldest = table.remove(logs, 1)
			if oldest then
				oldest:Destroy()
				logCount = logCount - 1
			else
				break
			end
		end
	end

	local function escapeRich(text)
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	local function addLog(message, messageType)
		message = tostring(message or "")
		if message == "" then return end
		trimLogs()

		counter = counter + 1
		local color = ConsoleColors[messageType] or NullUI.Theme.Text

		local entry = Instance.new("TextLabel")
		entry.Name = "Entry"
		entry.BackgroundTransparency = 1
		entry.RichText = true
		entry.FontFace = NullUI.Theme.FontRegular
		entry.TextSize = 12
		entry.TextWrapped = true
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.TextYAlignment = Enum.TextYAlignment.Top
		entry.LineHeight = 1.25
		entry.AutomaticSize = Enum.AutomaticSize.Y
		entry.Size = UDim2.new(1, 0, 0, 14)
		entry.LayoutOrder = counter
		entry.ZIndex = Z.Content + 2
		entry.Text = string.format(
			'<font color="#%s" transparency="0.45">[%s]</font> <font color="#%s">%s</font>',
			NullUI.Theme.TextDim:ToHex(), os.date("%H:%M:%S"),
			color:ToHex(), escapeRich(message)
		)
		entry.Parent = logsScroll

		table.insert(logs, entry)
		logCount = logCount + 1
		emptyState.Visible = false

		if autoScroll then
			task.defer(function()
				logsScroll.CanvasPosition = Vector2.new(0, logsScroll.AbsoluteCanvasSize.Y)
			end)
		end
	end

	jan:Add(logsScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = logsScroll.CanvasPosition.Y >= logsScroll.AbsoluteCanvasSize.Y - logsScroll.AbsoluteWindowSize.Y - 20
		autoScroll = atBottom
	end))

	copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard then return end

		local lines = {}
		for _, entry in ipairs(logs) do
			local clean = entry.Text
				:gsub('<font[^>]*>', "")
				:gsub("</font>", "")
				:gsub("&lt;", "<")
				:gsub("&gt;", ">")
				:gsub("&amp;", "&")
			table.insert(lines, clean)
		end
		setclipboard(table.concat(lines, "\n"))

		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.15)
			end
		end)
	end)

	local function clearLogs()
		for _, entry in ipairs(logs) do
			entry:Destroy()
		end
		table.clear(logs)
		logCount = 0
		emptyState.Visible = true
	end

	clearBtn.MouseButton1Click:Connect(clearLogs)

	if opts.AutoCapture ~= false then
		local LogService = game:GetService("LogService")
		jan:Add(LogService.MessageOut:Connect(addLog))
	end

	return {
		Instance = container,
		Log = function(_, message, messageType) addLog(message, messageType) end,
		Clear = function() clearLogs() end,
		Destroy = function() container:Destroy() end,
	}
end

function Tab:AddTable(opts)
	opts = opts or {}
	local jan = self._janitor
	local title = opts.Title or "Table"
	local hasDesc = opts.Description and opts.Description ~= ""
	local columns = opts.Columns or {}
	local rowHeight = opts.RowHeight or 30
	local bodyHeight = opts.Height or 200
	local sortable = opts.Sortable ~= false
	local striped = opts.Striped ~= false

	local totalWeight = 0
	for _, col in ipairs(columns) do
		col.Weight = col.Weight or 1
		totalWeight = totalWeight + col.Weight
	end
	if totalWeight <= 0 then totalWeight = 1 end

	local function colAlign(col)
		if col.Align == "Right" then return Enum.TextXAlignment.Right end
		if col.Align == "Center" then return Enum.TextXAlignment.Center end
		return Enum.TextXAlignment.Left
	end

	local function colX(index)
		local w = 0
		for i = 1, index - 1 do w = w + columns[i].Weight end
		return w / totalWeight
	end

	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local COLHEAD_H = 26
	local GAP1, GAP2 = 10, 6
	local colHeadY = PAD + HEADER_H + GAP1
	local scrollY = colHeadY + COLHEAD_H + GAP2
	local totalHeight = scrollY + bodyHeight + PAD

	local container = Instance.new("Frame")
	container.Name = "Table"
	BindTheme(container, "BackgroundColor3", "Surface")
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, totalHeight)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, NullUI.Theme.CornerRadiusSm)
	Stroke(container, Color3.new(1, 1, 1), 1, 0.92)
	self._window:_RegisterSearchable(self, title, container)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = NullUI.Theme.Font
	titleLabel.Text = title
	BindTheme(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, PAD)
	titleLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = container

	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = NullUI.Theme.FontRegular
		descLabel.Text = opts.Description
		BindTheme(descLabel, "TextColor3", "TextDim")
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(PAD, PAD + 18)
		descLabel.Size = UDim2.new(1, -PAD * 2, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = container
	end

	local colHead = Instance.new("Frame")
	colHead.Name = "ColumnHeader"
	colHead.BackgroundTransparency = 1
	colHead.Position = UDim2.fromOffset(PAD, colHeadY)
	colHead.Size = UDim2.new(1, -PAD * 2, 0, COLHEAD_H)
	colHead.ZIndex = Z.Content + 1
	colHead.Parent = container

	local sortState = { Key = nil, Asc = true }
	local headerLabels = {}

	for ci, col in ipairs(columns) do
		local x0 = colX(ci)
		local wFrac = col.Weight / totalWeight

		local cellBtn = Instance.new("TextButton")
		cellBtn.Name = "Col" .. ci
		cellBtn.Text = ""
		cellBtn.AutoButtonColor = false
		cellBtn.BackgroundTransparency = 1
		cellBtn.Position = UDim2.new(x0, ci > 1 and 4 or 0, 0, 0)
		cellBtn.Size = UDim2.new(wFrac, ci > 1 and -4 or 0, 1, 0)
		cellBtn.ZIndex = Z.Content + 2
		cellBtn.Parent = colHead

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = NullUI.Theme.Font
		lbl.Text = tostring(col.Label or col.Key or "")
		BindTheme(lbl, "TextColor3", "TextDim")
		lbl.TextSize = 12
		lbl.TextXAlignment = colAlign(col)
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.ZIndex = Z.Content + 3
		lbl.Parent = cellBtn

		headerLabels[col.Key] = { Lbl = lbl, Text = tostring(col.Label or col.Key or "") }

		if sortable then
			cellBtn.MouseEnter:Connect(function()
				if sortState.Key ~= col.Key then Tween(lbl, { TextColor3 = NullUI.Theme.Text }, 0.12) end
			end)
			cellBtn.MouseLeave:Connect(function()
				if sortState.Key ~= col.Key then Tween(lbl, { TextColor3 = NullUI.Theme.TextDim }, 0.12) end
			end)
		end
	end

	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, colHeadY + COLHEAD_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, scrollY)
	scroll.Size = UDim2.new(1, 0, 0, bodyHeight)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = Z.Content + 1
	scroll.Parent = container

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingLeft = UDim.new(0, PAD)
	scrollPad.PaddingRight = UDim.new(0, PAD)
	scrollPad.Parent = scroll

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = scroll

	AddScrollbar(scroll)
	AddContentScrollThumb(scroll, rowsLayout, container, jan)

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = NullUI.Theme.FontRegular
	emptyLabel.Text = "No rows"
	BindTheme(emptyLabel, "TextColor3", "TextDim")
	emptyLabel.TextSize = 12
	emptyLabel.Position = UDim2.fromOffset(PAD, scrollY + 10)
	emptyLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	emptyLabel.Visible = false
	emptyLabel.ZIndex = Z.Content + 1
	emptyLabel.Parent = container

	local currentRows = {}
	local rowFrames = {}

	local function clearRowFrames()
		for _, f in ipairs(rowFrames) do f:Destroy() end
		table.clear(rowFrames)
	end

	local function renderRows()
		clearRowFrames()
		emptyLabel.Visible = #currentRows == 0
		for ri, row in ipairs(currentRows) do
			local rowFrame = Instance.new("Frame")
			rowFrame.Name = "Row" .. ri
			rowFrame.BackgroundColor3 = Color3.new(1, 1, 1)
			rowFrame.BackgroundTransparency = (striped and ri % 2 == 0) and 0.97 or 1
			rowFrame.BorderSizePixel = 0
			rowFrame.LayoutOrder = ri
			rowFrame.Size = UDim2.new(1, 0, 0, rowHeight)
			rowFrame.ZIndex = Z.Content + 2
			rowFrame.Parent = scroll

			for ci, col in ipairs(columns) do
				local x0 = colX(ci)
				local wFrac = col.Weight / totalWeight

				local cell = Instance.new("TextLabel")
				cell.Name = "Cell" .. ci
				cell.BackgroundTransparency = 1
				cell.FontFace = NullUI.Theme.FontRegular
				cell.Text = tostring(row[col.Key] == nil and "" or row[col.Key])
				BindTheme(cell, "TextColor3", "Text")
				cell.TextSize = 12
				cell.TextXAlignment = colAlign(col)
				cell.TextTruncate = Enum.TextTruncate.AtEnd
				cell.Position = UDim2.new(x0, ci > 1 and 4 or 0, 0, 0)
				cell.Size = UDim2.new(wFrac, ci > 1 and -4 or 0, 1, 0)
				cell.ZIndex = Z.Content + 3
				cell.Parent = rowFrame
			end

			table.insert(rowFrames, rowFrame)
		end
	end

	local function compareValues(av, bv)
		local an, bn = tonumber(av), tonumber(bv)
		if an and bn then
			if an == bn then return 0 end
			return an < bn and -1 or 1
		end
		local as, bs = tostring(av or ""), tostring(bv or "")
		if as == bs then return 0 end
		return as < bs and -1 or 1
	end

	local function applySort()
		if not sortState.Key then return end
		table.sort(currentRows, function(a, b)
			local c = compareValues(a[sortState.Key], b[sortState.Key])
			if sortState.Asc then return c < 0 else return c > 0 end
		end)
		renderRows()
	end

	if sortable then
		for ci, col in ipairs(columns) do
			local cellBtn = colHead:FindFirstChild("Col" .. ci)
			if cellBtn then
				cellBtn.MouseButton1Click:Connect(function()
					if sortState.Key == col.Key then
						sortState.Asc = not sortState.Asc
					else
						sortState.Key = col.Key
						sortState.Asc = true
					end
					for key, info in pairs(headerLabels) do
						local arrow = ""
						if key == sortState.Key then arrow = sortState.Asc and "  \226\150\178" or "  \226\150\188" end
						info.Lbl.Text = info.Text .. arrow
						info.Lbl.TextColor3 = (key == sortState.Key) and NullUI.Theme.Text or NullUI.Theme.TextDim
					end
					applySort()
				end)
			end
		end
	end

	local api = {
		Instance = container,
		SetRows = function(_, rows)
			currentRows = rows or {}
			if sortState.Key then applySort() else renderRows() end
		end,
		GetRows = function() return currentRows end,
		Destroy = function() container:Destroy() end,
	}

	api:SetRows(opts.Rows or {})

	return api
end

local function Serialize(value)
	local t = typeof(value)
	if t == "Color3" then
		return { __t = "Color3", r = value.R, g = value.G, b = value.B }
	elseif t == "EnumItem" then
		return { __t = "Enum", v = tostring(value) }
	elseif t == "table" then
		local out = {}
		for i, v in ipairs(value) do out[i] = Serialize(v) end
		return out
	end
	return value
end

local function Deserialize(value)
	if type(value) ~= "table" then return value end
	if value.__t == "Color3" then
		return Color3.new(value.r, value.g, value.b)
	elseif value.__t == "Enum" then
		local parts = string.split(value.v, ".")
		local ok, result = pcall(function()
			return Enum[parts[2]][parts[3]]
		end)
		return ok and result or nil
	end
	local out = {}
	for i, v in ipairs(value) do out[i] = Deserialize(v) end
	return out
end

function Tab:AddCardGrid(opts)
	opts = opts or {}
	local height = opts.Height or 380
	local sorts = opts.Sorts or {}
	local pageSize = opts.PageSize or 20
	local showSearch = opts.Search ~= false
	local descriptionHeight = opts.DescriptionHeight or 28
	local showNativeScrollbar = opts.ShowScrollbar == true
	local cardPadding = opts.CardPadding or 10

	local outer = Instance.new("Frame")
	outer.Name = "CardGrid"
	outer.BackgroundColor3 = Color3.new(1, 1, 1)
	outer.BackgroundTransparency = 0.97
	outer.BorderSizePixel = 0
	outer.Size = UDim2.new(1, 0, 0, height)
	outer.ZIndex = Z.Content
	outer.Parent = self._page
	Corner(outer, NullUI.Theme.CornerRadiusSm)
	Stroke(outer, Color3.new(1, 1, 1), 1, 0.95)
	self._window:_RegisterSearchable(self, opts.Title or "Cards", outer)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = Z.Content + 1
	content.Parent = outer

	local OUTER_V_PAD = opts.OuterPadding or 18
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, OUTER_V_PAD)
	pad.PaddingBottom = UDim.new(0, OUTER_V_PAD)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = content

	local TOP_H, TABS_H = 32, 28
	local headerH = 0
	if showSearch then headerH = headerH + TOP_H end
	if #sorts > 1 then
		if headerH > 0 then headerH = headerH + 8 end
		headerH = headerH + TABS_H
	end
	if headerH > 0 then headerH = headerH + 10 end

	local searchBox
	if showSearch then
		local searchPill = Instance.new("Frame")
		searchPill.BackgroundColor3 = Color3.new(1, 1, 1)
		searchPill.BackgroundTransparency = 0.92
		searchPill.BorderSizePixel = 0
		searchPill.Size = UDim2.new(1, 0, 0, TOP_H)
		searchPill.ZIndex = Z.Content + 1
		searchPill.Parent = content
		Corner(searchPill, 9)
		local searchStroke = Stroke(searchPill, Color3.new(1, 1, 1), 1, 0.88)

		local searchIcon = Instance.new("ImageLabel")
		searchIcon.BackgroundTransparency = 1
		searchIcon.Image = ResolveIcon("search")
		BindTheme(searchIcon, "ImageColor3", "TextDim")
		searchIcon.Size = UDim2.fromOffset(13, 13)
		searchIcon.AnchorPoint = Vector2.new(0, 0.5)
		searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
		searchIcon.ZIndex = Z.Content + 2
		searchIcon.Parent = searchPill

		searchBox = Instance.new("TextBox")
		searchBox.ClearTextOnFocus = false
		searchBox.FontFace = NullUI.Theme.FontRegular
		searchBox.PlaceholderText = opts.SearchPlaceholder or "Search by name / tags..."
		searchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
		searchBox.Text = ""
		BindTheme(searchBox, "TextColor3", "Text")
		searchBox.TextSize = 13
		searchBox.TextXAlignment = Enum.TextXAlignment.Left
		searchBox.TextYAlignment = Enum.TextYAlignment.Center
		searchBox.BackgroundTransparency = 1
		searchBox.ClipsDescendants = true
		searchBox.Position = UDim2.fromOffset(30, 0)
		searchBox.Size = UDim2.new(1, -40, 1, 0)
		searchBox.ZIndex = Z.Content + 2
		searchBox.Parent = searchPill

		searchBox.Focused:Connect(function()
			Tween(searchStroke, { Color = NullUI.Theme.Accent, Transparency = 0.3 }, 0.15)
		end)
		searchBox.FocusLost:Connect(function()
			Tween(searchStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		end)
	end

	local currentSort = opts.DefaultSort or sorts[1]
	local sortButtons = {}
	if #sorts > 1 then
		local tabsRow = Instance.new("Frame")
		tabsRow.BackgroundTransparency = 1
		tabsRow.Position = UDim2.fromOffset(0, showSearch and (TOP_H + 8) or 0)
		tabsRow.Size = UDim2.new(1, 0, 0, TABS_H)
		tabsRow.ZIndex = Z.Content + 1
		tabsRow.Parent = content

		local tabsLayout = Instance.new("UIListLayout")
		tabsLayout.FillDirection = Enum.FillDirection.Horizontal
		tabsLayout.Padding = UDim.new(0, 6)
		tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabsLayout.Parent = tabsRow

		for i, sortName in ipairs(sorts) do
			local btn = Instance.new("TextButton")
			btn.AutoButtonColor = false
			btn.Text = ""
			btn.BackgroundColor3 = Color3.new(1, 1, 1)
			btn.BackgroundTransparency = (sortName == currentSort) and 0.85 or 1
			btn.BorderSizePixel = 0
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.Size = UDim2.fromOffset(0, TABS_H)
			btn.LayoutOrder = i
			btn.ZIndex = Z.Content + 1
			btn.Parent = tabsRow
			Corner(btn, 7)

			local btnPad = Instance.new("UIPadding")
			btnPad.PaddingLeft = UDim.new(0, 10)
			btnPad.PaddingRight = UDim.new(0, 10)
			btnPad.Parent = btn

			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = NullUI.Theme.Font
			lbl.Text = string.upper(sortName)
			lbl.TextColor3 = (sortName == currentSort) and NullUI.Theme.Text or NullUI.Theme.TextDim
			lbl.TextSize = 11
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.fromOffset(0, TABS_H)
			lbl.ZIndex = Z.Content + 2
			lbl.Parent = btn

			sortButtons[sortName] = { Button = btn, Label = lbl }
		end
	end

	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.BackgroundTransparency = 1
	gridScroll.BorderSizePixel = 0
	gridScroll.Position = UDim2.fromOffset(0, headerH)
	gridScroll.Size = UDim2.new(1, 0, 1, -headerH)
	gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	gridScroll.ScrollingEnabled = true
	gridScroll.Active = true
	gridScroll.ElasticBehavior = Enum.ElasticBehavior.Never
	gridScroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	gridScroll.ScrollBarThickness = showNativeScrollbar and (opts.ScrollBarThickness or 4) or 0
	BindTheme(gridScroll, "ScrollBarImageColor3", "TextDim")
	gridScroll.ScrollBarImageTransparency = 0.35
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridScroll.ZIndex = Z.Content + 1
	gridScroll.Parent = content

	-- Reserve room for the visible scrollbar so cards never sit underneath it.
	local GRID_RIGHT_PAD = gridScroll.ScrollBarThickness > 0 and (gridScroll.ScrollBarThickness + 6) or 16
	local GRID_TOP_PAD = 8
	local GRID_BOTTOM_PAD = 8
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, GRID_TOP_PAD)
	gridPad.PaddingRight = UDim.new(0, GRID_RIGHT_PAD)
	gridPad.Parent = gridScroll

	local MIN_CELL_W = opts.CardMinWidth or opts.CardWidth or 190
	local FIXED_COLUMNS = opts.Columns
	local MAX_COLUMNS = opts.MaxColumns
	local CELL_H = opts.CardHeight or 88
	local CELL_GAP = 8

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	gridLayout.CellSize = UDim2.fromOffset(MIN_CELL_W, CELL_H)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridScroll

	local function updateGridCanvas()
		gridScroll.CanvasSize = UDim2.new(
			0, 0, 0,
			math.max(0, (gridLayout.AbsoluteContentSize.Y / GetUIScale()) + GRID_TOP_PAD + GRID_BOTTOM_PAD)
		)
	end
	self._janitor:Add(ObserveProperties({{gridLayout, "AbsoluteContentSize"}}, updateGridCanvas))
	task.defer(updateGridCanvas)

	local SAFETY_MARGIN = 4
	local currentColumns = 1
	local function relayoutGridColumns()
		local availableW = (gridScroll.AbsoluteSize.X / GetUIScale()) - GRID_RIGHT_PAD - SAFETY_MARGIN
		if availableW <= 0 then return end
		local columns = FIXED_COLUMNS and math.max(1, FIXED_COLUMNS)
			or math.max(1, math.floor((availableW + CELL_GAP) / (MIN_CELL_W + CELL_GAP)))
		if not FIXED_COLUMNS and MAX_COLUMNS then columns = math.min(columns, math.max(1, MAX_COLUMNS)) end
		local cellW = math.floor((availableW - (columns - 1) * CELL_GAP) / columns)
		currentColumns = columns
		gridLayout.CellSize = UDim2.fromOffset(math.max(1, cellW), CELL_H)
	end
	BindWidthLayout(gridScroll, relayoutGridColumns)
	task.defer(relayoutGridColumns)

	if not showNativeScrollbar then
		AddScrollbar(gridScroll)
		AddContentScrollThumb(gridScroll, gridLayout, outer, self._janitor)
	end

	local MAX_OUTER_H = opts.Height or 300
	local showingCards = false

	local function applyOuterHeight(target)
		Tween(outer, { Size = UDim2.new(1, 0, 0, target) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end

	local EMPTY_STATE_H = 220
	local function resizeOuterEmpty()
		showingCards = false
		if opts.FixedHeight then
			applyOuterHeight(MAX_OUTER_H)
			return
		end
		applyOuterHeight(math.min(headerH + OUTER_V_PAD + EMPTY_STATE_H + OUTER_V_PAD, MAX_OUTER_H))
	end

	local function resizeOuterToGridContent()
		if not showingCards then return end
		if opts.FixedHeight then
			applyOuterHeight(MAX_OUTER_H)
			return
		end
		local contentH = gridLayout.AbsoluteContentSize.Y
		if contentH <= 0 then return end
		local target = math.min(headerH + OUTER_V_PAD + contentH + OUTER_V_PAD, MAX_OUTER_H)
		applyOuterHeight(target)
	end
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeOuterToGridContent)

	local statusHolder = Instance.new("Frame")
	statusHolder.BackgroundTransparency = 1
	statusHolder.Position = UDim2.fromOffset(0, headerH)
	statusHolder.Size = UDim2.new(1, 0, 1, -headerH)
	statusHolder.Visible = false
	statusHolder.ZIndex = Z.Content + 2
	statusHolder.Parent = content

	local statusLayout = Instance.new("UIListLayout")
	statusLayout.FillDirection = Enum.FillDirection.Vertical
	statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statusLayout.Padding = UDim.new(0, 6)
	statusLayout.Parent = statusHolder

	local statusIcon = Instance.new("ImageLabel")
	statusIcon.BackgroundTransparency = 1
	BindTheme(statusIcon, "ImageColor3", "TextDim")
	statusIcon.Size = UDim2.fromOffset(24, 24)
	statusIcon.LayoutOrder = 1
	statusIcon.Visible = false
	statusIcon.ZIndex = Z.Content + 3
	statusIcon.Parent = statusHolder

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.FontFace = NullUI.Theme.FontRegular
	BindTheme(statusLabel, "TextColor3", "TextDim")
	statusLabel.TextSize = 12
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.Size = UDim2.new(1, -20, 0, 16)
	statusLabel.LayoutOrder = 2
	statusLabel.ZIndex = Z.Content + 3
	statusLabel.Parent = statusHolder

	local STATUS_ICONS = { loading = "loader-circle", empty = "frown", error = "triangle-alert" }

	local function openCardMenu(anchor, actions)
		if type(actions) ~= "table" or #actions == 0 then return end

		local popup, backdrop
		local function closeMenu()
			RegisterPopupClose(closeMenu)
			if backdrop then backdrop:Destroy(); backdrop = nil end
			if popup then popup:Destroy(); popup = nil end
		end

		RegisterPopupOpen(closeMenu)
		backdrop = MakePopupBackdrop(closeMenu)

		local rowH, gap, pad = 32, 2, 8
		local popupW = 190
		local popupH = pad * 2 + #actions * rowH + math.max(0, #actions - 1) * gap
		local scale = GetUIScale()
		local view = ViewportSize()
		local anchorPos, anchorSize = anchor.AbsolutePosition, anchor.AbsoluteSize
		local px = (anchorPos.X + anchorSize.X) / scale - popupW
		local py = (anchorPos.Y + anchorSize.Y) / scale + 5
		px = SafeClamp(px, 8, view.X / scale - popupW - 8)
		py = SafeClamp(py, 8, view.Y / scale - popupH - 8)

		popup = Instance.new("Frame")
		popup.ClipsDescendants = true
		popup.Name = "CardActionsPopup"
		popup.Active = true
		BindTheme(popup, "BackgroundColor3", "Background")
		popup.BackgroundTransparency = 0.04
		popup.BorderSizePixel = 0
		popup.Position = UDim2.fromOffset(math.round(px), math.round(py))
		popup.Size = UDim2.fromOffset(popupW, popupH)
		popup.ZIndex = Z.Popup
		popup.Parent = NullUI._Root
		Corner(popup, 10)
		Stroke(popup, Color3.new(1, 1, 1), 1, 0.9)
		GlassLayer(popup, 10, 0.985)

		local actionsHolder = Instance.new("Frame")
		actionsHolder.Name = "Actions"
		actionsHolder.BackgroundTransparency = 1
		actionsHolder.Size = UDim2.fromScale(1, 1)
		actionsHolder.ZIndex = Z.Popup + 1
		actionsHolder.Parent = popup

		local popupPad = Instance.new("UIPadding")
		popupPad.PaddingTop = UDim.new(0, pad)
		popupPad.PaddingBottom = UDim.new(0, pad)
		popupPad.PaddingLeft = UDim.new(0, pad)
		popupPad.PaddingRight = UDim.new(0, pad)
		popupPad.Parent = actionsHolder

		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, gap)
		popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		popupLayout.Parent = actionsHolder

		for i, action in ipairs(actions) do
			local button = Instance.new("TextButton")
			button.Name = "Action" .. i
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = Color3.new(1, 1, 1)
			button.BackgroundTransparency = 1
			button.BorderSizePixel = 0
			button.Size = UDim2.new(1, 0, 0, rowH)
			button.LayoutOrder = i
			button.ZIndex = Z.Popup + 1
			button.Parent = actionsHolder
			Corner(button, 7)

			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Image = ResolveIcon(action.Icon or "circle")
			icon.ImageColor3 = action.Danger and NullUI.Theme.Danger or NullUI.Theme.TextDim
			icon.Size = UDim2.fromOffset(14, 14)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 9, 0.5, 0)
			icon.ZIndex = Z.Popup + 2
			icon.Parent = button

			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.FontFace = NullUI.Theme.FontRegular
			label.Text = tostring(action.Text or "Action")
			label.TextColor3 = action.Danger and NullUI.Theme.Danger or NullUI.Theme.Text
			label.TextSize = 12
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Position = UDim2.fromOffset(31, 0)
			label.Size = UDim2.new(1, -39, 1, 0)
			label.ZIndex = Z.Popup + 2
			label.Parent = button

			button.MouseEnter:Connect(function()
				Tween(button, { BackgroundTransparency = 0.9 }, 0.1)
			end)
			button.MouseLeave:Connect(function()
				Tween(button, { BackgroundTransparency = 1 }, 0.1)
			end)
			button.MouseButton1Click:Connect(function()
				closeMenu()
				if action.Callback then task.spawn(action.Callback) end
			end)
		end
	end

	local function buildCard(item, animDelay)
		local cell = Instance.new("Frame")
		cell.Name = "GridCard"
		cell.BackgroundColor3 = Color3.new(1, 1, 1)
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.ClipsDescendants = true
		cell.ZIndex = Z.Content + 2
		cell.Parent = gridScroll
		Corner(cell, NullUI.Theme.CornerRadiusSm)
		local cellStroke = Stroke(cell, Color3.new(1, 1, 1), 1, 1)

		local cellScale = Instance.new("UIScale")
		cellScale.Scale = 0.9
		cellScale.Parent = cell

		task.delay(animDelay or 0, function()
			if not cell.Parent then return end
			Tween(cell, { BackgroundTransparency = 0.94 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween(cellStroke, { Transparency = 0.9 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween(cellScale, { Scale = 1 }, 0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)

		local cellPad = Instance.new("UIPadding")
		cellPad.PaddingTop = UDim.new(0, cardPadding)
		cellPad.PaddingBottom = UDim.new(0, cardPadding)
		cellPad.PaddingLeft = UDim.new(0, cardPadding)
		cellPad.PaddingRight = UDim.new(0, cardPadding)
		cellPad.Parent = cell

		local textX = 0
		if item.Icon then
			local ICON_BOX = 24
			local iconHolder = Instance.new("Frame")
			iconHolder.BackgroundColor3 = Color3.new(1, 1, 1)
			iconHolder.BackgroundTransparency = 0.9
			iconHolder.BorderSizePixel = 0
			iconHolder.Size = UDim2.fromOffset(ICON_BOX, ICON_BOX)
			iconHolder.ZIndex = Z.Content + 3
			iconHolder.Parent = cell
			Corner(iconHolder, 7)

			local iconImg = Instance.new("ImageLabel")
			iconImg.BackgroundTransparency = 1
			iconImg.Image = ResolveIcon(item.Icon)
			BindTheme(iconImg, "ImageColor3", "Accent")
			iconImg.Size = UDim2.fromOffset(13, 13)
			iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			iconImg.Position = UDim2.fromScale(0.5, 0.5)
			iconImg.ZIndex = Z.Content + 4
			iconImg.Parent = iconHolder

			textX = ICON_BOX + 8
		end

		local hasPrimaryAction = item.Callback ~= nil
		local hasSecondaryAction = item.SecondaryCallback ~= nil
		local hasMenuAction = item.Menu and #item.Menu > 0
		local trailingReserve = (hasPrimaryAction and 26 or 0)
			+ (hasSecondaryAction and 30 or 0)
			+ (hasMenuAction and 30 or 0)
		if hasPrimaryAction then

			local actionBadge = Instance.new("Frame")
			actionBadge.Name = "LoadBadge"
			BindTheme(actionBadge, "BackgroundColor3", "Accent")
			actionBadge.BackgroundTransparency = 0.8
			actionBadge.BorderSizePixel = 0
			actionBadge.AnchorPoint = Vector2.new(1, 0)
			actionBadge.Position = UDim2.new(1, 0, 0, 0)
			actionBadge.Size = UDim2.fromOffset(22, 22)
			actionBadge.ZIndex = Z.Content + 6
			actionBadge.Parent = cell
			Corner(actionBadge, 7)

			local actionIcon = Instance.new("ImageLabel")
			actionIcon.BackgroundTransparency = 1
			actionIcon.Image = ResolveIcon(item.ActionIcon or "download")
			BindTheme(actionIcon, "ImageColor3", "Accent")
			actionIcon.Size = UDim2.fromOffset(12, 12)
			actionIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			actionIcon.Position = UDim2.fromScale(0.5, 0.5)
			actionIcon.ZIndex = Z.Content + 7
			actionIcon.Parent = actionBadge

			local actionClick = Instance.new("TextButton")
			actionClick.Text = ""
			actionClick.AutoButtonColor = false
			actionClick.BackgroundTransparency = 1
			actionClick.Size = UDim2.fromScale(1, 1)
			actionClick.ZIndex = Z.Content + 8
			actionClick.Parent = actionBadge
			actionClick.MouseButton1Click:Connect(function()
				item.Callback()
			end)
		end

		if hasSecondaryAction then
			local secondaryBadge = Instance.new("Frame")
			secondaryBadge.Name = "SecondaryActionBadge"
			secondaryBadge.BackgroundColor3 = item.SecondaryDanger
				and Color3.fromRGB(225, 76, 88)
				or NullUI.Theme.Accent
			secondaryBadge.BackgroundTransparency = item.SecondaryDanger and 0.82 or 0.8
			secondaryBadge.BorderSizePixel = 0
			secondaryBadge.AnchorPoint = Vector2.new(1, 0)
			secondaryBadge.Position = UDim2.new(1, hasPrimaryAction and -30 or 0, 0, 0)
			secondaryBadge.Size = UDim2.fromOffset(22, 22)
			secondaryBadge.ZIndex = Z.Content + 6
			secondaryBadge.Parent = cell
			Corner(secondaryBadge, 7)

			local secondaryIcon = Instance.new("ImageLabel")
			secondaryIcon.BackgroundTransparency = 1
			secondaryIcon.Image = ResolveIcon(item.SecondaryIcon or "trash-2")
			secondaryIcon.ImageColor3 = item.SecondaryDanger
				and Color3.fromRGB(255, 125, 135)
				or NullUI.Theme.Accent
			secondaryIcon.Size = UDim2.fromOffset(12, 12)
			secondaryIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			secondaryIcon.Position = UDim2.fromScale(0.5, 0.5)
			secondaryIcon.ZIndex = Z.Content + 7
			secondaryIcon.Parent = secondaryBadge

			local secondaryClick = Instance.new("TextButton")
			secondaryClick.Text = ""
			secondaryClick.AutoButtonColor = false
			secondaryClick.BackgroundTransparency = 1
			secondaryClick.Size = UDim2.fromScale(1, 1)
			secondaryClick.ZIndex = Z.Content + 8
			secondaryClick.Parent = secondaryBadge
			secondaryClick.MouseButton1Click:Connect(function()
				item.SecondaryCallback()
			end)
		end

		if hasMenuAction then
			local menuBadge = Instance.new("Frame")
			menuBadge.Name = "MenuBadge"
			BindTheme(menuBadge, "BackgroundColor3", "Accent")
			menuBadge.BackgroundTransparency = 0.8
			menuBadge.BorderSizePixel = 0
			menuBadge.AnchorPoint = Vector2.new(1, 0)
			menuBadge.Position = UDim2.new(
				1,
				-((hasPrimaryAction and 30 or 0) + (hasSecondaryAction and 30 or 0)),
				0,
				0
			)
			menuBadge.Size = UDim2.fromOffset(22, 22)
			menuBadge.ZIndex = Z.Content + 6
			menuBadge.Parent = cell
			Corner(menuBadge, 7)

			local menuIcon = Instance.new("ImageLabel")
			menuIcon.BackgroundTransparency = 1
			menuIcon.Image = ResolveIcon("Lucide:settings")
			BindTheme(menuIcon, "ImageColor3", "Accent")
			menuIcon.Size = UDim2.fromOffset(12, 12)
			menuIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			menuIcon.Position = UDim2.fromScale(0.5, 0.5)
			menuIcon.ZIndex = Z.Content + 7
			menuIcon.Parent = menuBadge

			local menuClick = Instance.new("TextButton")
			menuClick.Text = ""
			menuClick.AutoButtonColor = false
			menuClick.BackgroundTransparency = 1
			menuClick.Size = UDim2.fromScale(1, 1)
			menuClick.ZIndex = Z.Content + 8
			menuClick.Parent = menuBadge
			menuClick.MouseButton1Click:Connect(function()
				openCardMenu(menuBadge, item.Menu)
			end)
		end

		local cursorY = 0

		local titleLbl = Instance.new("TextLabel")
		titleLbl.BackgroundTransparency = 1
		titleLbl.FontFace = NullUI.Theme.Font
		titleLbl.Text = item.Title or "Untitled"
		BindTheme(titleLbl, "TextColor3", "Text")
		titleLbl.TextSize = 13
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextYAlignment = Enum.TextYAlignment.Center
		titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
		titleLbl.Position = UDim2.fromOffset(textX, item.Icon and 4 or cursorY)
		titleLbl.Size = UDim2.new(1, -(textX + trailingReserve), 0, item.Icon and 24 or 16)
		titleLbl.ZIndex = Z.Content + 3
		titleLbl.Parent = cell
		cursorY = math.max(item.Icon and (24 + 6) or 0, cursorY + 16 + 3)

		if item.Description and item.Description ~= "" then

			local descLbl = Instance.new("TextLabel")
			descLbl.BackgroundTransparency = 1
			descLbl.FontFace = NullUI.Theme.FontRegular
			descLbl.Text = item.Description
			BindTheme(descLbl, "TextColor3", "TextDim")
			descLbl.TextSize = 11
			descLbl.TextWrapped = true
			descLbl.TextTruncate = Enum.TextTruncate.None
			descLbl.TextXAlignment = Enum.TextXAlignment.Left
			descLbl.TextYAlignment = Enum.TextYAlignment.Top
			descLbl.Position = UDim2.fromOffset(0, cursorY)
			descLbl.Size = UDim2.new(1, -trailingReserve, 0, descriptionHeight)
			descLbl.ZIndex = Z.Content + 3
			descLbl.Parent = cell
			cursorY = cursorY + descriptionHeight + 3
		end

		if item.Byline and item.Byline ~= "" then
			local bylineLbl = Instance.new("TextLabel")
			bylineLbl.BackgroundTransparency = 1
			bylineLbl.FontFace = NullUI.Theme.FontRegular
			bylineLbl.Text = item.Byline
			BindTheme(bylineLbl, "TextColor3", "TextDim")
			bylineLbl.TextTransparency = 0.25
			bylineLbl.TextSize = 10
			bylineLbl.TextXAlignment = Enum.TextXAlignment.Left
			bylineLbl.TextTruncate = Enum.TextTruncate.AtEnd
			bylineLbl.Position = UDim2.fromOffset(0, cursorY)
			bylineLbl.Size = UDim2.new(1, -trailingReserve, 0, 12)
			bylineLbl.ZIndex = Z.Content + 3
			bylineLbl.Parent = cell
		end

		if item.Stats and #item.Stats > 0 then
			local statsRow = Instance.new("Frame")
			statsRow.BackgroundTransparency = 1
			statsRow.AnchorPoint = Vector2.new(0, 1)
			statsRow.Position = UDim2.new(0, 0, 1, 0)
			statsRow.Size = UDim2.new(1, 0, 0, 16)
			statsRow.ZIndex = Z.Content + 3
			statsRow.Parent = cell

			local statsLayout = Instance.new("UIListLayout")
			statsLayout.FillDirection = Enum.FillDirection.Horizontal
			statsLayout.Padding = UDim.new(0, 10)
			statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
			statsLayout.Parent = statsRow

			for i, stat in ipairs(item.Stats) do

				local statFrame = Instance.new(stat.Callback and "TextButton" or "Frame")
				statFrame.BackgroundTransparency = 1
				statFrame.AutomaticSize = Enum.AutomaticSize.X
				statFrame.Size = UDim2.fromOffset(0, 14)
				statFrame.LayoutOrder = i
				statFrame.ZIndex = Z.Content + 3
				statFrame.Parent = statsRow
				if stat.Callback then
					statFrame.Text = ""
					statFrame.AutoButtonColor = false
				end

				local statLayout = Instance.new("UIListLayout")
				statLayout.FillDirection = Enum.FillDirection.Horizontal
				statLayout.VerticalAlignment = Enum.VerticalAlignment.Center
				statLayout.Padding = UDim.new(0, 3)
				statLayout.Parent = statFrame

				local statIcon = Instance.new("ImageLabel")
				statIcon.BackgroundTransparency = 1
				statIcon.Image = ResolveIcon(stat.Icon or "circle")
				BindTheme(statIcon, "ImageColor3", "TextDim")
				statIcon.Size = UDim2.fromOffset(11, 11)
				statIcon.LayoutOrder = 1
				statIcon.ZIndex = Z.Content + 4
				statIcon.Parent = statFrame

				local statLbl = Instance.new("TextLabel")
				statLbl.BackgroundTransparency = 1
				statLbl.FontFace = NullUI.Theme.FontRegular
				statLbl.Text = tostring(stat.Text or "")
				BindTheme(statLbl, "TextColor3", "TextDim")
				statLbl.TextSize = 10
				statLbl.AutomaticSize = Enum.AutomaticSize.X
				statLbl.Size = UDim2.fromOffset(0, 12)
				statLbl.LayoutOrder = 2
				statLbl.ZIndex = Z.Content + 4
				statLbl.Parent = statFrame

				if stat.Callback then
					statFrame.MouseEnter:Connect(function()
						Tween(statIcon, { ImageColor3 = NullUI.Theme.Accent }, 0.1)
						Tween(statLbl, { TextColor3 = NullUI.Theme.Accent }, 0.1)
					end)
					statFrame.MouseLeave:Connect(function()
						Tween(statIcon, { ImageColor3 = NullUI.Theme.TextDim }, 0.1)
						Tween(statLbl, { TextColor3 = NullUI.Theme.TextDim }, 0.1)
					end)
					statFrame.MouseButton1Click:Connect(function()
						task.spawn(stat.Callback)
					end)
				end
			end
		end

		if item.Callback then

			local hasInteractiveStat = false
			if item.Stats then
				for _, stat in ipairs(item.Stats) do
					if stat.Callback then hasInteractiveStat = true end
				end
			end

			local click = Instance.new("TextButton")
			click.Text = ""
			click.AutoButtonColor = false
			click.BackgroundTransparency = 1
			click.Size = hasInteractiveStat and UDim2.new(1, 0, 1, -20) or UDim2.fromScale(1, 1)
			click.ZIndex = Z.Content + 5
			click.Parent = cell

			click.MouseEnter:Connect(function()
				Tween(cell, { BackgroundTransparency = 0.88 }, 0.12)
				Tween(cellStroke, { Transparency = 0.8 }, 0.12)
			end)
			click.MouseLeave:Connect(function()
				Tween(cell, { BackgroundTransparency = 0.94 }, 0.12)
				Tween(cellStroke, { Transparency = 0.9 }, 0.12)
			end)
			click.MouseButton1Click:Connect(function()
				task.spawn(item.Callback)
			end)
		end

		return cell
	end

	local currentQuery = ""
	local loadToken = 0

	local function clearGrid()
		for _, child in ipairs(gridScroll:GetChildren()) do
			if child.Name == "GridCard" then child:Destroy() end
		end
	end

	local function setStatus(msg, kind)
		local visible = msg ~= nil and msg ~= ""
		statusLabel.Text = msg or ""
		statusHolder.Visible = visible
		local iconName = visible and STATUS_ICONS[kind]
		statusIcon.Visible = iconName ~= nil
		if iconName then
			statusIcon.Image = ResolveIcon(iconName)
		end
	end

	local function computeCellHeight(items)
		local hasIcon, hasDesc, hasByline, hasStats = false, false, false, false
		for _, item in ipairs(items) do
			if item.Icon then hasIcon = true end
			if item.Description and item.Description ~= "" then hasDesc = true end
			if item.Byline and item.Byline ~= "" then hasByline = true end
			if item.Stats and #item.Stats > 0 then hasStats = true end
		end
		local h = 20
		h = h + (hasIcon and 24 or 16) + 3
		if hasDesc then h = h + descriptionHeight + 3 end
		if hasByline then h = h + 12 end
		if hasStats then h = h + 16 + 4 end
		return h
	end

	local function refresh()
		if not opts.Fetch then return end
		loadToken = loadToken + 1
		local myToken = loadToken
		clearGrid()
		setStatus(opts.LoadingText or "Loading...", "loading")
		resizeOuterEmpty()
		task.spawn(function()
			local ok, items, fetchErr = pcall(opts.Fetch, {
				Query = currentQuery,
				Sort = currentSort,
				PageSize = pageSize,
			})
			if myToken ~= loadToken then return end
			if not ok then
				setStatus(opts.ErrorText or tostring(items), "error")
				resizeOuterEmpty()
				return
			end
			if fetchErr then
				setStatus(opts.ErrorText or tostring(fetchErr), "error")
				resizeOuterEmpty()
				return
			end
			items = items or {}
			if #items == 0 then
				setStatus(opts.EmptyText or "Nothing here yet.", "empty")
				resizeOuterEmpty()
				return
			end
			setStatus(nil)
			if opts.AutoCardHeight ~= false then
				CELL_H = math.max(computeCellHeight(items), opts.MinCardHeight or 0)
				gridLayout.CellSize = UDim2.new(
					gridLayout.CellSize.X.Scale, gridLayout.CellSize.X.Offset,
					0, CELL_H
				)
			end
			showingCards = true
			for i, item in ipairs(items) do

				buildCard(item, math.min(i - 1, 8) * 0.035)
			end

			task.spawn(function()
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
				if myToken == loadToken then resizeOuterToGridContent() end
			end)
		end)
	end

	if searchBox then
		local debounceToken = 0
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			currentQuery = searchBox.Text
			debounceToken = debounceToken + 1
			local myDebounce = debounceToken
			task.delay(0.35, function()
				if myDebounce == debounceToken then refresh() end
			end)
		end)
	end

	for sortName, entry in pairs(sortButtons) do
		entry.Button.MouseButton1Click:Connect(function()
			if currentSort == sortName then return end
			currentSort = sortName
			for otherName, otherEntry in pairs(sortButtons) do
				local active = otherName == currentSort
				Tween(otherEntry.Button, { BackgroundTransparency = active and 0.85 or 1 }, 0.12)
				Tween(otherEntry.Label, { TextColor3 = active and NullUI.Theme.Text or NullUI.Theme.TextDim }, 0.12)
			end
			refresh()
		end)
	end

	if opts.AutoLoad ~= false and opts.Fetch then
		task.defer(refresh)
	end

	return {
		Instance = outer,
		Refresh = refresh,
		SetQuery = function(_, q)
			currentQuery = q or ""
			if searchBox then searchBox.Text = currentQuery end
			refresh()
		end,
		SetSort = function(_, s)
			currentSort = s
			refresh()
		end,
		Destroy = function() outer:Destroy() end,
	}
end

function NullUI:GetConfig()
	local data = {}
	for flag, api in pairs(NullUI.Flags) do
		if api.Get then
			local ok, value = pcall(api.Get)
			if ok then data[flag] = Serialize(value) end
		end
	end
	return data
end

function NullUI:SetConfig(data, silent)
	if type(data) ~= "table" then return false end
	for flag, raw in pairs(data) do
		local api = NullUI.Flags[flag]
		if api and api.Set then
			pcall(api.Set, api, Deserialize(raw), silent ~= false)
		end
	end
	return true
end

function NullUI:ListUIElements()
	local out = {}
	for flag, api in pairs(NullUI.Flags) do
		local ok, value = pcall(api.Get)
		table.insert(out, {
			Flag  = flag,
			Kind  = api.Kind,
			Label = api.Label,
			Value = ok and value or nil,
		})
	end
	table.sort(out, function(a, b) return a.Flag < b.Flag end)
	return out
end

function NullUI:SetUIElementValue(flag, value, silent)
	local api = NullUI.Flags[flag]
	if not api or not api.Set then
		return false, "Unknown UI element: " .. tostring(flag)
	end
	local ok, err = pcall(api.Set, api, value, silent ~= false)
	if not ok then return false, tostring(err) end
	return true
end

local CONFIGS_FOLDER = "NullUI/Configs"

local function EnsureConfigsFolder()
	if not (fn_isfolder and fn_makefolder) then return false end
	local ok = pcall(function()
		if not fn_isfolder("NullUI") then fn_makefolder("NullUI") end
		if not fn_isfolder(CONFIGS_FOLDER) then fn_makefolder(CONFIGS_FOLDER) end
	end)
	return ok
end

local function SafeConfigName(name)
	name = tostring(name or "config"):gsub("[^%w_%- ]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then name = "config" end
	return name
end

local function ConfigPath(name)
	return CONFIGS_FOLDER .. "/" .. SafeConfigName(name) .. ".json"
end

local function LegacyConfigPath(name)
	return "NullUI/" .. SafeConfigName(name) .. ".json"
end

local function BuildConfigEnvelope(name, data, meta)
	meta = meta or {}
	return {
		Schema      = 1,
		Name        = name,
		Description = meta.Description or "",
		Tags        = meta.Tags or {},
		CreatedAt   = meta.CreatedAt or os.time(),
		Data        = data,
	}
end

local function ReadConfigFile(path)
	if not (fn_isfile and fn_readfile) then return nil, "readfile unavailable" end
	local existsOk, exists = pcall(fn_isfile, path)
	if not existsOk or not exists then return nil, "config does not exist" end
	local ok, raw = pcall(fn_readfile, path)
	if not ok then return nil, raw end
	local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not decodeOk then return nil, "failed to decode config" end
	if type(decoded) ~= "table" then return nil, "malformed config" end

	if decoded.Data == nil then
		return BuildConfigEnvelope(nil, decoded, {}), nil
	end
	return decoded, nil
end

function NullUI:SaveConfig(name, opts)
	if not fn_writefile then return false, "writefile unavailable" end
	opts = opts or {}
	EnsureConfigsFolder()
	name = name or "config"
	local envelope = BuildConfigEnvelope(name, NullUI:GetConfig(), opts)
	local ok, err = pcall(function()
		fn_writefile(ConfigPath(name), HttpService:JSONEncode(envelope))
	end)
	return ok, err
end

function NullUI:LoadConfig(name, silent)
	name = name or "config"
	local envelope, err = ReadConfigFile(ConfigPath(name))
	if not envelope then
		envelope, err = ReadConfigFile(LegacyConfigPath(name))
	end
	if not envelope then return false, err end
	return NullUI:SetConfig(envelope.Data, silent)
end

function NullUI:GetConfigMeta(name)
	local envelope, err = ReadConfigFile(ConfigPath(name))
	if not envelope then return nil, err end
	return {
		Name        = envelope.Name or name,
		Description = envelope.Description or "",
		Tags        = envelope.Tags or {},
		CreatedAt   = envelope.CreatedAt,
	}
end

function NullUI:GetSavedConfig(name)
	local envelope, err = ReadConfigFile(ConfigPath(name))
	if not envelope then return nil, err end
	return envelope, nil
end

function NullUI:ListConfigs()
	if not fn_listfiles then return {}, "listfiles unavailable" end
	EnsureConfigsFolder()
	local ok, files = pcall(fn_listfiles, CONFIGS_FOLDER)
	if not ok or type(files) ~= "table" then return {}, "failed to list configs" end

	local out = {}
	for _, path in ipairs(files) do
		if tostring(path):match("%.json$") then
			local envelope = ReadConfigFile(path)
			if envelope then
				local fileName = tostring(path):match("([^/\\]+)%.json$") or envelope.Name
				table.insert(out, {
					Name        = envelope.Name or fileName,
					FileName    = fileName,
					Description = envelope.Description or "",
					Tags        = envelope.Tags or {},
					CreatedAt   = envelope.CreatedAt or 0,
				})
			end
		end
	end

	table.sort(out, function(a, b) return (a.CreatedAt or 0) > (b.CreatedAt or 0) end)
	return out, nil
end

function NullUI:DeleteConfig(name)
	if not (fn_isfile and fn_delfile) then return false, "delfile unavailable" end
	local path = ConfigPath(name)
	local ok, exists = pcall(fn_isfile, path)
	if not ok or not exists then return false, "config does not exist" end
	local delOk, err = pcall(fn_delfile, path)
	return delOk, err
end

function NullUI:RenameConfig(oldName, newName)
	local envelope, err = ReadConfigFile(ConfigPath(oldName))
	if not envelope then return false, err end
	envelope.Name = newName
	local ok, writeErr = pcall(function()
		EnsureConfigsFolder()
		fn_writefile(ConfigPath(newName), HttpService:JSONEncode(envelope))
	end)
	if not ok then return false, writeErr end
	if ConfigPath(oldName) ~= ConfigPath(newName) then
		pcall(fn_delfile, ConfigPath(oldName))
	end
	return true
end

function NullUI:CreateSnapshot()
	return { Data = NullUI:GetConfig(), CreatedAt = os.time() }
end

function NullUI:RestoreSnapshot(snapshot, silent)
	if type(snapshot) ~= "table" or type(snapshot.Data) ~= "table" then
		return false, "invalid snapshot"
	end
	return NullUI:SetConfig(snapshot.Data, silent)
end

function NullUI:SetLayoutDebug(enabled)
	if self._DebugJanitor then self._DebugJanitor:Destroy(); self._DebugJanitor = nil end
	if not enabled then return end
	local jan = Janitor.new()
	self._DebugJanitor = jan
	LibJanitor:Add(jan)
	local function mark(object)
		if not object:IsA("GuiObject") or object.Name == "LayoutDebug" then return end
		local outline = Instance.new("Frame")
		outline.Name = "LayoutDebug"
		outline.BackgroundTransparency = 1
		outline.Size = UDim2.fromScale(1, 1)
		outline.ZIndex = Z.Toast + 20
		outline.Parent = self._Root
		Stroke(outline, Color3.fromRGB(0, 220, 180), 1, 0.45)
		jan:Add(outline)
		local targets = {{object, "AbsolutePosition", "AbsoluteSize", "Visible"}}
		local ancestor = object.Parent
		while ancestor and ancestor:IsA("GuiObject") do
			table.insert(targets, {ancestor, "Visible"})
			ancestor = ancestor.Parent
		end
		jan:Add(ObserveProperties(targets, function()
			local visible = object.Parent ~= nil
			local current = object
			while current and current:IsA("GuiObject") do
				visible = visible and current.Visible
				current = current.Parent
			end
			outline.Visible = visible
			local scale = GetUIScale()
			local position = object.AbsolutePosition - self._Root.AbsolutePosition
			outline.Position = UDim2.fromOffset(position.X / scale, position.Y / scale)
			outline.Size = UDim2.fromOffset(object.AbsoluteSize.X / scale, object.AbsoluteSize.Y / scale)
		end))
	end
	for _, window in ipairs(self._Windows) do
		local descendants = window._gui:GetDescendants()
		mark(window._gui)
		for _, object in ipairs(descendants) do mark(object) end
	end
end

function Window:ShowNotificationHistory()
	if not self._HistoryTab then self._HistoryTab = self:AddTab({Name = "Notifications", Icon = "bell", Hidden = true}) end
	for _, card in ipairs(self._HistoryCards or {}) do card:Destroy() end
	self._HistoryCards = {}
	local history = NullUI:GetNotificationHistory()
	if #history == 0 then
		local paragraph = self._HistoryTab:AddParagraph({Title = "No notifications", Text = "Notifications will appear here after being shown."})
		table.insert(self._HistoryCards, paragraph.Instance)
	else
		for i = #history, 1, -1 do
			local item = history[i]
			local paragraph = self._HistoryTab:AddParagraph({Title = item.Title, Text = item.Text})
			table.insert(self._HistoryCards, paragraph.Instance)
		end
	end
	self._HistoryTab._select()
end

function Window:AddUIPreferences()
	if self._PreferencesTab then return self._PreferencesTab end
	local tab = self:AddTab({Name = "Interface", Icon = "settings"})
	self._PreferencesTab = tab
	tab:AddDropdown({Text = "Density", Options = {"comfortable", "compact"}, Default = NullUI:GetDensity(), Callback = function(mode) NullUI:SetDensity(mode) end})
	tab:AddButton({Text = "Restore window layout", Callback = function() self:ResetLayout() end})
	tab:AddButton({Text = "Notification history", Callback = function() self:ShowNotificationHistory() end})
	tab:AddButton({Text = "Clear notification history", Callback = function() NullUI:ClearNotificationHistory() end})
	tab:AddDropdown({Text = "Profile name", Options = {"display", "username", "anonymous"}, Default = (self._UserInfoOptions or {}).NameMode or "display", Callback = function(mode) self:SetUserInfo({NameMode = mode}) end})
	tab:AddTextbox({Text = "Profile image", Placeholder = "player or rbxassetid", Default = tostring((self._UserInfoOptions or {}).Avatar or "player"), Callback = function(image) self:SetUserInfo({Avatar = image ~= "" and image or "player"}) end})
	return tab
end

local function DestroyAllWindowJanitors()
	for _, win in ipairs(NullUI._Windows) do
		win._destroyed = true
		if win._janitor then win._janitor:Destroy() end
	end
	table.clear(NullUI._Windows)
end

NullUI._Root.Destroying:Connect(function()
	AcrylicShuttingDown = true
	DestroyAllWindowJanitors()
	DestroyAllAcrylicControllers()
	LibJanitor:Destroy()
end)

function NullUI:Unload()
	CloseAnyOpenPopup()
	AcrylicShuttingDown = true
	DestroyAllWindowJanitors()
	DestroyAllAcrylicControllers()
	LibJanitor:Destroy()
	if NullUI._Root then NullUI._Root:Destroy() end
end

do
	local globalTable = GetGlobalTable()
	globalTable.__NullUI_Unload = function()
		pcall(function() NullUI:Unload() end)
	end
end

local function CollapsibleHeading(header, title, inset, token, rightAligned, leadingIcon)
 header.Text = ""
 local icon = Instance.new("ImageLabel")
 icon.Name = "CollapseChevron"
 icon.BackgroundTransparency = 1
 icon.Size = UDim2.fromOffset(14, 14)
 icon.AnchorPoint = Vector2.new(rightAligned and 1 or 0, 0.5)
 icon.Position = rightAligned and UDim2.new(1, -inset, 0.5, 0) or UDim2.new(0, inset, 0.5, 0)
 icon.Image = ResolveIcon("Lucide:chevron-down")
 BindTheme(icon, "ImageColor3", token)
 icon.Parent = header
 local label = Instance.new("TextLabel")
 label.Name = "HeadingText"
 label.BackgroundTransparency = 1
 label.Position = UDim2.fromOffset(rightAligned and inset or (inset + 22), 0)
 label.Size = UDim2.new(1, -(inset + 32), 1, 0)
 label.FontFace = header.FontFace
 label.TextSize = header.TextSize
 label.TextXAlignment = Enum.TextXAlignment.Left
 label.TextTruncate = Enum.TextTruncate.AtEnd
 label.Text = title
 BindTheme(label, "TextColor3", token)
 label.Parent = header
 if leadingIcon and rightAligned then
  local symbol = Instance.new("ImageLabel")
  symbol.Name = "SectionIcon"
  symbol.BackgroundTransparency = 1
  symbol.Size = UDim2.fromOffset(16, 16)
  symbol.AnchorPoint = Vector2.new(0, 0.5)
  symbol.Position = UDim2.new(0, inset, 0.5, 0)
  symbol.Image = ResolveIcon(leadingIcon)
  BindTheme(symbol, "ImageColor3", token)
  symbol.Parent = header
  label.Position = UDim2.fromOffset(inset + 24, 0)
  label.Size = UDim2.new(1, -(inset + 56), 1, 0)
 end
 return icon
end

local function AnimateCollapsibleBody(body, chevron, janitor)
 local clip = Instance.new("Frame")
 clip.Name = "CollapseViewport"
 clip.BackgroundTransparency = 1
 clip.ClipsDescendants = true
 clip.LayoutOrder = body.LayoutOrder
 clip.Size = UDim2.new(1, 0, 0, 0)
 clip.Parent = body.Parent
 body.Parent = clip
 local collapsed, initialized = false, false
 local heightTween, arrowTween, completion
 local targetHeight = -1
 local disposed = false
 local function cancelHeight()
  if completion then completion:Disconnect(); completion = nil end
  if heightTween then heightTween:Cancel(); heightTween = nil end
 end
 local function apply(immediate)
  if disposed then return end
  local height = collapsed and 0 or math.max(0, body.AbsoluteSize.Y / GetUIScale())
  if height == targetHeight and not immediate then return end
  targetHeight = height
  cancelHeight()
  clip.Visible = true
  if immediate then
   clip.Size = UDim2.new(1, 0, 0, height)
   clip.Visible = not collapsed
   return
  end
  heightTween = TweenService:Create(clip, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, height)})
  completion = heightTween.Completed:Connect(function()
   if completion then completion:Disconnect(); completion = nil end
   clip.Visible = not collapsed
  end)
  heightTween:Play()
 end
 janitor:Add(body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
  if disposed then return end
  local height = collapsed and 0 or math.max(0, body.AbsoluteSize.Y / GetUIScale())
  if math.abs(height - targetHeight) < 0.5 then return end
  -- Layout changes must not restart an animation on every resize frame.
  apply(true)
 end))
 janitor:Add(function()
  disposed = true
  cancelHeight()
  if arrowTween then arrowTween:Cancel() end
 end)
 return function(value)
  local nextCollapsed = value == true
  if initialized and nextCollapsed == collapsed then return end
  collapsed = nextCollapsed
  if arrowTween then arrowTween:Cancel() end
  if not initialized and chevron then
   chevron.Rotation = collapsed and -90 or 0
  elseif chevron then
   arrowTween = Tween(chevron, {Rotation = collapsed and -90 or 0}, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
  end
  apply(not initialized)
  initialized = true
 end
end

function Window:AddTabGroup(options)
	options = type(options) == "string" and {Name = options} or (options or {})
	local group = {Tabs = {}, Collapsed = options.Collapsed == true}
	local frame = Instance.new("Frame")
	frame.Name = "TabGroup"
	frame.ZIndex = Z.Content
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = self._tabBar
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local header = Instance.new("TextButton")
	header.AutoButtonColor = false
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 28)
	header.FontFace = NullUI.Theme.Font
	header.TextSize = 12
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextTruncate = Enum.TextTruncate.AtEnd
	BindTheme(header, "TextColor3", "TextDim")
	header.Parent = frame
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = frame
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	local chevron = CollapsibleHeading(header, options.Name or "Group", 6, "TextDim")
	local animate = AnimateCollapsibleBody(body, chevron, self._janitor)
	function group:SetCollapsed(value)
		self.Collapsed = value == true
		animate(self.Collapsed)
		for _, tab in ipairs(self.Tabs or {}) do
			if tab._window._currentTab == tab then tab._window._tabIndicator.Visible = not self.Collapsed end
		end
	end
	function group:Toggle() self:SetCollapsed(not self.Collapsed) end
	local window = self
	function group:AddTab(opts)
		local tab = window:AddTab(opts)
		if not tab.Hidden then tab._button.Parent = body end
		tab._SidebarGroup = self
		table.insert(self.Tabs, tab)
		return tab
	end
	self._janitor:Add(header.Activated:Connect(function() group:Toggle() end))
	group:SetCollapsed(group.Collapsed)
	group.Instance = frame
	return group
end

function Tab:AddCollapsibleSection(options)
	options = type(options) == "string" and {Title = options} or (options or {})
	local frame = BaseCard(self._page, 0)
	frame.Name = "CollapsibleSection"
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local header = Instance.new("TextButton")
	header.BackgroundTransparency = 1
	header.AutoButtonColor = false
	header.Size = UDim2.new(1, 0, 0, 36)
	header.FontFace = NullUI.Theme.Font
	header.TextSize = 14
	header.TextTruncate = Enum.TextTruncate.AtEnd
	header.TextXAlignment = Enum.TextXAlignment.Left
	BindTheme(header, "TextColor3", "Text")
	header.Parent = frame
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = frame
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingLeft = UDim.new(0, 10)
	bodyPad.PaddingRight = UDim.new(0, 10)
	bodyPad.PaddingBottom = UDim.new(0, 10)
	bodyPad.Parent = body
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	local parent = self
	local section = setmetatable({Name = self.Name, Instance = frame, _page = body, _window = self._window,
		_group = self._group, _janitor = self._janitor, _RootTab = self._RootTab or self,
		_ParentSection = self._IsSection and self or nil, _IsSection = true}, Tab)
	local chevron = CollapsibleHeading(header, options.Title or options.Text or "Section", 12, "Text", true, options.Icon)
	local animate = AnimateCollapsibleBody(body, chevron, self._janitor)
	function section:SetCollapsed(value)
		self.Collapsed = value == true
		animate(self.Collapsed)
		for _, tab in ipairs(self.Tabs or {}) do
			if tab._window._currentTab == tab then tab._window._tabIndicator.Visible = not self.Collapsed end
		end
	end
	function section:Toggle() self:SetCollapsed(not self.Collapsed) end
	function section:Expand()
		if self._ParentSection then self._ParentSection:Expand() end
		self:SetCollapsed(false)
	end
	section._select = function()
  if parent._select then parent._select()
  elseif parent._parentTab then parent._parentTab._select(); parent._parentTab:SelectSubTab(parent._subTabIdx) end
  section:Expand()
 end
	self._janitor:Add(header.Activated:Connect(function() section:Toggle() end))
	section:SetCollapsed(options.Collapsed == true)
	return section
end

local function EmbeddedPage(parent, body, selectPage)
 return setmetatable({Name = parent.Name, _page = body, _window = parent._window,
  _group = parent._group, _janitor = parent._janitor,
  _RootTab = parent._RootTab or parent, _select = selectPage}, Tab)
end

local function SelectEmbeddedParent(parent)
 if parent._select then parent._select()
 elseif parent._parentTab then parent._parentTab._select(); parent._parentTab:SelectSubTab(parent._subTabIdx) end
end

function Tab:AddTabBox(options)
 options = options or {}
 local parent = self
 local frame = BaseCard(self._page, 0)
 frame.Name = "TabBox"
 frame.BackgroundTransparency = 0.98
 frame.AutomaticSize = Enum.AutomaticSize.Y
 local inset = Instance.new("UIPadding")
 inset.PaddingLeft = UDim.new(0, 12)
 inset.PaddingRight = UDim.new(0, 12)
 inset.PaddingTop = UDim.new(0, 12)
 inset.PaddingBottom = UDim.new(0, 12)
 inset.Parent = frame
 local layout = Instance.new("UIListLayout")
 layout.SortOrder = Enum.SortOrder.LayoutOrder
 layout.Parent = frame
 local bar = Instance.new("ScrollingFrame")
 bar.Name = "TabBoxTabs"
 bar.BackgroundTransparency = 1
 BindTheme(bar, "BackgroundColor3", "Accent")
 Corner(bar, 8)
 bar.BorderSizePixel = 0
 bar.Size = UDim2.new(1, 0, 0, 40)
 bar.CanvasSize = UDim2.new()
 bar.AutomaticCanvasSize = Enum.AutomaticSize.X
 bar.ScrollingDirection = Enum.ScrollingDirection.X
 bar.ScrollBarThickness = 2
 BindTheme(bar, "ScrollBarImageColor3", "TextDim")
 bar.Parent = frame
 local row = Instance.new("UIListLayout")
 row.FillDirection = Enum.FillDirection.Horizontal
 row.SortOrder = Enum.SortOrder.LayoutOrder
 row.Padding = UDim.new(0, 4)
 row.Parent = bar
 local box = {Instance = frame, Tabs = {}}
 local transition, completion
 local generation = 0
 local function cancelTransition()
  generation = generation + 1
  if completion then completion:Disconnect(); completion = nil end
  if transition then transition:Cancel(); transition = nil end
 end
 parent._janitor:Add(cancelTransition)
 local function resizeButtons()
  local count = #box.Tabs
  if count == 0 then return end
  local available = bar.AbsoluteSize.X / GetUIScale()
  local width = math.max(80, (available - (count - 1) * 4) / count)
  for _, tab in ipairs(box.Tabs) do tab._button.Size = UDim2.fromOffset(width, 36) end
 end
 parent._janitor:Add(BindWidthLayout(bar, resizeButtons))
 function box:SelectTab(value)
  local selected
  for index, tab in ipairs(self.Tabs) do
   if value == index or value == tab.Name or value == tab then selected = tab; break end
  end
  if not selected then return end
  if self.Selected == selected then return end
  local previous = self.Selected
  cancelTransition()
  local token = generation
  self.Selected = selected
  local function reveal()
   if token ~= generation or not frame.Parent then return end
   for _, item in ipairs(self.Tabs) do item._page.Visible = item == selected end
   selected._page.GroupTransparency = previous and 1 or 0
   if previous then
    transition = Tween(selected._page, {GroupTransparency = 0}, 0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
   end
  end
  if previous and previous._page.Visible then
   transition = TweenService:Create(previous._page, TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {GroupTransparency = 1})
   completion = transition.Completed:Connect(function()
    if completion then completion:Disconnect(); completion = nil end
    reveal()
   end)
   transition:Play()
  else
   reveal()
  end
  for _, tab in ipairs(self.Tabs) do
   BindTheme(tab._button, "TextColor3", tab == selected and "Text" or "TextDim")
   if tab._label then BindTheme(tab._label, "TextColor3", tab == selected and "Text" or "TextDim") end
   if tab._icon then BindTheme(tab._icon, "ImageColor3", tab == selected and "Text" or "TextDim") end
   Tween(tab._button, {BackgroundTransparency = tab == selected and 0.96 or 1}, 0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
   Tween(tab._underline, {BackgroundTransparency = tab == selected and 0.1 or 1}, 0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
  end
 end
 function box:AddTab(value)
  local opts = type(value) == "string" and {Name = value} or (value or {})
  local button = Instance.new("TextButton")
  button.AutoButtonColor = false
  button.Text = opts.Name or "Tab"
  button.FontFace = NullUI.Theme.Font
  button.TextSize = 13
  button.TextTruncate = Enum.TextTruncate.AtEnd
  button.Size = UDim2.fromOffset(math.max(80, MeasureText(button.Text, 13) + 28), 34)
  button.BackgroundTransparency = 1
  BindTheme(button, "BackgroundColor3", "Accent")
  Corner(button, 7)
  button.Parent = bar
  local underline = Instance.new("Frame")
  underline.Name = "ActiveUnderline"
  underline.BorderSizePixel = 0
  underline.AnchorPoint = Vector2.new(0.5, 1)
  underline.Position = UDim2.new(0.5, 0, 1, 0)
  underline.Size = UDim2.new(1, -24, 0, 2)
  underline.BackgroundTransparency = 1
  BindTheme(underline, "BackgroundColor3", "Accent")
  Corner(underline, 2)
  underline.Parent = button
  local icon, label
  if opts.Icon then
   button.Text = ""
   icon = Instance.new("ImageLabel")
   icon.BackgroundTransparency = 1
   icon.Size = UDim2.fromOffset(15, 15)
   icon.AnchorPoint = Vector2.new(0, 0.5)
   icon.Position = UDim2.new(0, 10, 0.5, 0)
   icon.Image = ResolveIcon(opts.Icon)
   icon.Parent = button
   label = Instance.new("TextLabel")
   label.BackgroundTransparency = 1
   label.Position = UDim2.fromOffset(31, 0)
   label.Size = UDim2.new(1, -39, 1, -2)
   label.FontFace = button.FontFace
   label.TextSize = button.TextSize
   label.TextXAlignment = Enum.TextXAlignment.Left
   label.TextTruncate = Enum.TextTruncate.AtEnd
   label.Text = opts.Name or "Tab"
   label.Parent = button
  end
  local body = Instance.new("CanvasGroup")
  body.GroupTransparency = 0
  body.BackgroundTransparency = 1
  body.Size = UDim2.new(1, 0, 0, 0)
  body.AutomaticSize = Enum.AutomaticSize.Y
  body.LayoutOrder = 1
  body.Visible = false
  body.Parent = frame
  local padding = Instance.new("UIPadding")
  padding.PaddingLeft = UDim.new(0, 0)
  padding.PaddingRight = UDim.new(0, 0)
  padding.PaddingTop = UDim.new(0, 12)
  padding.PaddingBottom = UDim.new(0, 0)
  padding.Parent = body
  local list = Instance.new("UIListLayout")
  list.Padding = UDim.new(0, 12)
  list.SortOrder = Enum.SortOrder.LayoutOrder
  list.Parent = body
  local tab
  tab = EmbeddedPage(parent, body, function() SelectEmbeddedParent(parent); box:SelectTab(tab) end)
  tab.Name = opts.Name or "Tab"
  tab._icon = icon
  tab._label = label
  tab._button = button
  tab._underline = underline
  table.insert(self.Tabs, tab)
  resizeButtons()
  parent._janitor:Add(button.Activated:Connect(function() box:SelectTab(tab) end))
  if not self.Selected then box:SelectTab(tab)
  else
   BindTheme(button, "TextColor3", "TextDim")
   if label then BindTheme(label, "TextColor3", "TextDim") end
   if icon then BindTheme(icon, "ImageColor3", "TextDim") end
  end
  return tab
 end
 return box
end

function Tab:AddToggleSection(options)
 options = options or {}
 local section = self:AddCollapsibleSection({Title = options.Title or "Settings", Icon = options.Icon, Collapsed = options.Collapsed})
 local toggle = section:AddToggle({Text = options.Text or "Enable", Default = options.Default == true, Flag = options.Flag, Callback = options.Callback})
 local body = Instance.new("Frame")
 body.Name = "DependentControls"
 body.BackgroundTransparency = 1
 body.Size = UDim2.new(1, 0, 0, 0)
 body.AutomaticSize = Enum.AutomaticSize.Y
 body.LayoutOrder = 1
 body.Parent = section._page
 local layout = Instance.new("UIListLayout")
 layout.Padding = UDim.new(0, 8)
 layout.SortOrder = Enum.SortOrder.LayoutOrder
 layout.Parent = body
 local animate = AnimateCollapsibleBody(body, nil, self._janitor)
 animate(not toggle:Get())
 self._janitor:Add(toggle:OnChanged(function(value) animate(not value) end))
 local originalSet = toggle.Set
 toggle.Set = function(handle, value, silent)
  originalSet(handle, value, silent)
  animate(not handle:Get())
 end
 local content = EmbeddedPage(section, body, function() section._select() end)
 content.Toggle = toggle
 content.Section = section
 content.Instance = section.Instance
 content.SetEnabled = function(_, value, silent) toggle:Set(value, silent) end
 content.GetEnabled = function() return toggle:Get() end
 content.SetCollapsed = function(_, value) section:SetCollapsed(value) end
 return content
end

function Window:SetBackground(options)
	options = type(options) == "string" and {Image = options} or (options or {})
	if not self._BackgroundImage then
		local image = Instance.new("ImageLabel")
		image.Name = "WindowBackground"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Crop
		image.ZIndex = Z.Glass
		image.Parent = self._gui
		Corner(image, NullUI.Theme.CornerRadius)
		self._BackgroundImage = image
	end
	self._BackgroundOptions = self._BackgroundOptions or {Image = "", Transparency = 0.7}
	for key, value in pairs(options) do self._BackgroundOptions[key] = value end
	local image = tostring(self._BackgroundOptions.Image or "")
	self._BackgroundImage.Image = image:match("^%d+$") and ("rbxassetid://" .. image) or image
	self._BackgroundImage.ImageTransparency = math.clamp(tonumber(self._BackgroundOptions.Transparency) or 0.7, 0, 1)
	self._BackgroundImage.Visible = image ~= ""
	return self
end

function Window:SetBackgroundTransparency(value)
 self._BackgroundTransparency = math.clamp(tonumber(value) or 0.15, 0, 1)
 self._gui.BackgroundTransparency = self._BackgroundTransparency
 return self
end

function Window:AddAppearanceTab(options)
	if self._AppearanceTab then return self._AppearanceTab end
	options = options or {}
	local tab = self:AddTab({Name = options.Name or "Appearance", Icon = "palette"})
	self._AppearanceTab = tab
	local themeSection = tab:AddCollapsibleSection({Title = "Theme and colors"})
	local pickers = {}
	themeSection:AddDropdown({Text = "Theme", Options = {"Dark", "Light", "Midnight", "Forest"}, Default = NullUI._ThemeName or "Dark", Callback = function(name)
		NullUI:SetTheme(name)
		for token, picker in pairs(pickers) do picker:Set(NullUI.Theme[token], true) end
	end})
	for _, entry in ipairs({{"Accent", "Accent"}, {"Background", "Background"}, {"Surface", "Surface"}, {"Text", "Text"}, {"TextDim", "Secondary text"}}) do
		local token = entry[1]
		pickers[token] = themeSection:AddColorPicker({Text = entry[2], Default = NullUI.Theme[token], Callback = function(color) NullUI:SetTheme({[token] = color}) end})
	end
	local opacitySection = tab:AddCollapsibleSection({Title = "Window background", Icon = "Lucide:blend"})
 opacitySection:AddSlider({Text = "Background transparency", Description = "0 = opaque, 100 = transparent", Min = 0, Max = 100, Default = (self._BackgroundTransparency or 0.15) * 100,
  Callback = function(value) self:SetBackgroundTransparency(value / 100) end})
 local imageSection = tab:AddCollapsibleSection({Title = "Background image"})
	imageSection:AddTextbox({Text = "Image", Description = "Numeric ID or rbxassetid://...", Default = "", Callback = function(value) self:SetBackground({Image = value}) end})
	imageSection:AddSlider({Text = "Transparency", Min = 0, Max = 100, Default = 70, Callback = function(value) self:SetBackground({Transparency = value / 100}) end})
	imageSection:AddButton({Text = "Remove image", Callback = function() self:SetBackground({Image = ""}) end})
	local effects = tab:AddCollapsibleSection({Title = "Effects"})
	effects:AddToggle({Text = "Blur", Default = NullUI.Config.Blur, Callback = function(enabled) NullUI:SetBlurEnabled(enabled) end})
	return tab
end

local IntegrationContext = {
	BindTheme = BindTheme,
	ASSETS_FOLDER = ASSETS_FOLDER,
	AddContentScrollThumb = AddContentScrollThumb,
	AddScrollbar = AddScrollbar,
	Corner = Corner,
	DetectFeedbackEvasion = DetectFeedbackEvasion,
	EnsureAssetsFolder = EnsureAssetsFolder,
	HttpService = HttpService,
	LocalPlayer = LocalPlayer,
	MeasureText = MeasureText,
	NormalizeFeedbackText = NormalizeFeedbackText,
	NullUI = NullUI,
	Players = Players,
	ResolveIcon = ResolveIcon,
	RunService = RunService,
	SafeConfigName = SafeConfigName,
	SanitizeFeedbackText = SanitizeFeedbackText,
	Stroke = Stroke,
	Tab = Tab,
	Tween = Tween,
	TweenService = TweenService,
	UserInputService = UserInputService,
	Window = Window,
	Z = Z,
	fn_customasset = fn_customasset,
	fn_isfile = fn_isfile,
	fn_readfile = fn_readfile,
	fn_writefile = fn_writefile,
	hasFn = hasFn,
}
NullUI._Modules = {}
function NullUI:Use(module)
	assert(type(module) == "table" and type(module.Name) == "string", "Use expects a VindUI module")
	if self._Modules[module.Name] then return self end
	if module.Modules then
		for _, child in ipairs(module.Modules) do self:Use(child) end
	else
		assert(module.API == 1 and type(module.Install) == "function", "Incompatible VindUI module")
		for _, dependency in ipairs(module.Requires or {}) do
			assert(self._Modules[dependency], "Load " .. dependency .. " before " .. module.Name)
		end
		module.Install(IntegrationContext)
	end
	self._Modules[module.Name] = true
	return self
end
function NullUI:HasModule(name) return self._Modules[name] == true end

return NullUI
