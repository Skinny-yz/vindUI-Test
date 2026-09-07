-- Vind UI Reborn - example usage
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

getgenv().CONFIG = {
	-- Choose which integration panels to show. Restart after changing these.
	Integrations = {
		Spotify = false,
		Assistant = false,
		Cloud = false,
		GlobalChat = false,
	},
	MobileScaleReference = 450,
	UserInfo = {
		Enabled = true,
		Avatar = "player", -- "player", numeric ID, or "rbxassetid://..."
		NameMode = "display", -- "display", "username", or "anonymous"
	},
	FeedbackWebhook = "",
	CloudBaseUrl = "",
	SpotifyBridgeUrl = "",
	SpotifyConnectUrl = "",
	OpenRouterApiKey = "",
	CommunityUrl = "https://github.com/Skinny-yz/vindUI-Test",
}

local VindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Skinny-yz/vindUI-Test/main/full.luau"))()
VindUI:PreloadIcons({ "Lucide" })
VindUI:SetScaleRange(0.75, 1.35) -- Desktop
VindUI:SetMobileScaleReference(getgenv().CONFIG.MobileScaleReference)

local TOGGLE_KEY = Enum.KeyCode.RightShift
local Tabs = {}

local Window = VindUI:CreateWindow({
	Title = "Vind Ui Reborn",
	Subtitle = "Interactive Showcase · v" .. tostring(VindUI.Version),
	Icon = "Lucide:sparkles",
	Size = UDim2.fromOffset(640, 455),
	MinSize = Vector2.new(500, 360),
	Draggable = true,
	Resizable = true,
	UseBlur = true,
	DefaultTab = "Home",
	TabScrollbar = true, -- false hides the sidebar scrollbar; scrolling stays enabled
	UserInfo = getgenv().CONFIG.UserInfo,
})

VindUI:Notify({
	Title = "Vind Ui Reborn",
	Text = "Showcase loaded. Use the search button to find any element.",
	Type = "success",
	Duration = 4,
})

-- Optional panels: loading a module alone does not create dock buttons.
local Cloud
if getgenv().CONFIG.Integrations.Cloud or getgenv().CONFIG.Integrations.GlobalChat then
	Cloud = VindUI:CloudService({
		BaseUrl = getgenv().CONFIG.CloudBaseUrl,
		Script = "vind-ui-reborn-showcase",
	})
end

if getgenv().CONFIG.Integrations.Spotify then
	Window:AddSpotifyPanel({
		Title = "Spotify Remote",
		Icon = "Lucide:music-2",
		BridgeUrl = getgenv().CONFIG.SpotifyBridgeUrl,
		ConnectUrl = getgenv().CONFIG.SpotifyConnectUrl,
		EmbedMode = true,
		AutoConnect = getgenv().CONFIG.SpotifyBridgeUrl ~= "",
	})
end

if getgenv().CONFIG.Integrations.Assistant then
	local ChatDockButton
	local Assistant = VindUI:CreateAIAssistant({
		Providers = {{
			Name = "OpenRouter",
			Endpoint = "https://openrouter.ai/api/v1/chat/completions",
			ApiKey = getgenv().CONFIG.OpenRouterApiKey,
			Model = "openrouter/free",
		}},
		Window = Window,
		Persist = "vind-showcase-assistant",
	})

	local ChatPanel = Window:AddChatPanel({
		Title = "Vind Assistant",
		Icon = "bot",
		Placeholder = "Ask about this interface...",
		OnToggle = function(open)
			if ChatDockButton then ChatDockButton:SetActive(open) end
		end,
		OnClear = function() Assistant:Reset() end,
		OnSend = function(panel, text)
			if getgenv().CONFIG.OpenRouterApiKey == "" then
				panel:AddMessage("assistant", "Add your API key to getgenv().CONFIG.OpenRouterApiKey to enable the assistant.")
				return
			end
			Assistant:Ask(panel, text)
		end,
		OnStop = function() Assistant:Stop() end,
		OnRegenerate = function(panel, text)
			if getgenv().CONFIG.OpenRouterApiKey ~= "" then Assistant:Ask(panel, text) end
		end,
	})

	ChatDockButton = Window:AddDockButton({
		Icon = "Lucide:bot",
		Callback = function() ChatPanel:Toggle() end,
	})
end

if getgenv().CONFIG.Integrations.Cloud then
	local CloudDockButton
	local CloudPanel = Window:AddCloudPanel({
		Service = Cloud,
		OnToggle = function(open)
			if CloudDockButton then CloudDockButton:SetActive(open) end
		end,
	})

	CloudDockButton = Window:AddDockButton({
		Icon = "Lucide:cloud",
		Callback = function() CloudPanel.Toggle() end,
	})
end

if getgenv().CONFIG.Integrations.GlobalChat then
	local GlobalChatDockButton
	local GlobalChatPanel = Window:AddGlobalChatPanel({
		Service = Cloud,
		Icon = "messages-square",
		OnToggle = function(open)
			if GlobalChatDockButton then GlobalChatDockButton:SetActive(open) end
		end,
	})

	GlobalChatDockButton = Window:AddDockButton({
		Icon = "Lucide:messages-square",
		Callback = function() GlobalChatPanel.Toggle() end,
	})
end

-- ==================== HOME ====================

-- Main navigation
local Main = Window:AddTabGroup({Name = "SHOWCASE"})
Tabs.Home = Main:AddTab({Name = "Home", Icon = "Lucide:house"})
Tabs.Controls = Main:AddTab({Name = "Controls", Icon = "Lucide:sliders-horizontal"})
Tabs.Layouts = Main:AddTab({Name = "Layouts", Icon = "Lucide:panels-top-left"})
local Tools = Window:AddTabGroup({Name = "WORKSPACE"})
Tabs.Settings = Tools:AddTab({Name = "Settings", Icon = "Lucide:settings-2"})
Tabs.About = Tools:AddTab({Name = "About", Icon = "Lucide:info"})

local function notify(title, message)
    VindUI:Notify({Title = title, Text = message, Type = "info", Duration = 3})
end
local function section(tab, title, icon, collapsed)
    return tab:AddCollapsibleSection({Title = title, Icon = "Lucide:" .. icon, Collapsed = collapsed == true})
end
local function slider(tab, text, flag, default, max)
    return tab:AddSlider({Text = text, Flag = flag, Min = 0, Max = max or 100, Default = default})
end

local Overview = Tabs.Home:AddSubTab({Name = "Overview", Icon = "Lucide:layout-dashboard"})
Overview:AddParagraph({Title = "Your workspace, your way", Icon = "Lucide:sparkles",
    Text = "A compact tour of Vind UI. Explore controls, nested tabs and adaptive sections. Use Ctrl+K to find a control."})
local Quick = section(Overview, "Quick actions", "zap")
Quick:AddButton({Text = "Preview notification", Icon = "Lucide:bell", Callback = function() notify("Hello!", "Notifications stay inside the screen.") end})
Quick:AddButton({Text = "Customize appearance", Icon = "Lucide:palette", Callback = function() Window:SelectTab("Appearance") end})
local Guide = Tabs.Home:AddSubTab({Name = "Guide", Icon = "Lucide:book-open"})
Guide:AddParagraph({Title = "Try the details", Text = "Resize the window, switch tabs quickly and collapse a section. On mobile, use landscape mode. All example controls are demonstrations; they do not automate gameplay."})

local Inputs = section(Tabs.Controls, "Essentials", "sliders-horizontal")
Inputs:AddToggle({Text = "Enable feature", Flag = "DemoEnabled", Default = false})
slider(Inputs, "Intensity", "Intensity", 50)
Inputs:AddDropdown({Text = "Mode", Flag = "Mode", Options = {"Balanced", "Performance", "Quality"}, Default = "Balanced"})
Inputs:AddTextbox({Text = "Profile name", Flag = "ProfileName", Default = "My workspace"})
local Style = section(Tabs.Controls, "Color and selection", "paintbrush")
Style:AddColorPicker({Text = "Highlight color", Flag = "Highlight", Default = Color3.fromRGB(120, 180, 255)})
Style:AddDropdown({Text = "Visible details", Flag = "Details", MultiSelect = true, Options = {"Names", "Distance", "Status"}, Default = {"Names", "Status"}})
local Actions = section(Tabs.Controls, "Actions", "mouse-pointer-2", true)
Actions:AddButton({Text = "Confirm an action", Icon = "Lucide:check", Callback = function()
    VindUI:Confirm({Title = "Confirm action", Text = "This is a preview. No data will be changed.", Window = Window,
        ConfirmText = "Confirm", CancelText = "Cancel", Callback = function(ok) if ok then notify("Confirmed", "The confirmation callback ran.") end end})
end})

-- Four nested tabs; settings are illustrative and keep their values when hidden.
local Box = Tabs.Layouts:AddTabBox()
local Farm = Box:AddTab({Name = "Auto Farm", Icon = "Lucide:sprout"})
local Options = Box:AddTab({Name = "Settings", Icon = "Lucide:settings-2"})
local Visuals = Box:AddTab({Name = "Visuals", Icon = "Lucide:eye"})
local Profiles = Box:AddTab({Name = "Profiles", Icon = "Lucide:folder"})
local General = section(Farm, "General", "sprout")
General:AddToggle({Text = "Enable demo", Flag = "FarmDemo", Default = false})
General:AddDropdown({Text = "Target mode", Options = {"Nearest", "Selected"}, Default = "Nearest"})
slider(section(Farm, "Limits", "shield", true), "Maximum targets", "TargetLimit", 3, 10)
slider(section(Options, "Range", "radius"), "Distance", "Distance", 25)
slider(section(Options, "Timing", "timer"), "Interval", "Interval", 2, 10)
local Indicators = section(Visuals, "Indicators", "scan-eye")
Indicators:AddToggle({Text = "Show target", Flag = "ShowTarget", Default = true})
Indicators:AddToggle({Text = "Show range", Flag = "ShowRange", Default = false})
local Presets = section(Profiles, "Preset", "folder-open")
Presets:AddDropdown({Text = "Preset", Options = {"Balanced", "Performance", "Custom"}, Default = "Balanced"})
Presets:AddParagraph({Title = "Keep your setup", Text = "Save the flagged controls from Settings. Appearance preferences are configured separately."})
local Audio = Tabs.Layouts:AddToggleSection({Title = "Audio Settings", Icon = "Lucide:volume-2", Text = "Enable Audio", Flag = "AudioEnabled", Default = false})
slider(Audio, "Volume", "Volume", 50)
Audio:AddDropdown({Text = "Output", Options = {"Music", "Effects", "All"}, Default = "All"})

local Profile = section(Tabs.Settings, "User profile", "user-round")
Profile:AddDropdown({Text = "Display name", Options = {"display", "username", "anonymous"}, Default = getgenv().CONFIG.UserInfo.NameMode,
    Callback = function(value) Window:SetUserInfo({NameMode = value}) end})
Profile:AddTextbox({Text = "Avatar", Description = "player or an image asset ID", Default = tostring(getgenv().CONFIG.UserInfo.Avatar),
    Callback = function(value) Window:SetUserInfo({Avatar = value}) end})
local Storage = section(Tabs.Settings, "Saved setup", "save")
Storage:AddButton({Text = "Save controls", Icon = "Lucide:save", Callback = function()
    local ok, err = VindUI:SaveConfig("showcase")
    notify(ok and "Saved" or "Unable to save", ok and "Your controls were saved." or tostring(err))
end})
Storage:AddButton({Text = "Load controls", Icon = "Lucide:folder-open", Callback = function()
    local ok, err = VindUI:LoadConfig("showcase")
    notify(ok and "Loaded" or "Unable to load", ok and "Your controls were restored." or tostring(err))
end})
local Layout = section(Tabs.Settings, "Window", "app-window", true)
Layout:AddButton({Text = "Reset layout", Callback = function() Window:ResetLayout() end})
Layout:AddButton({Text = "Notification history", Callback = function() Window:ShowNotificationHistory() end})
Window:AddAppearanceTab()
Tabs.About:AddParagraph({Title = "Vind UI Reborn", Icon = "Lucide:sparkles", Text = "Reusable controls, collapsible groups, animated tab boxes and optional integrations. This example loads one bundle and keeps configuration in getgenv().CONFIG."})
Tabs.About:AddButton({Text = "Copy repository link", Icon = "Lucide:github", Callback = function()
    if setclipboard then setclipboard(getgenv().CONFIG.CommunityUrl) else notify("Repository", getgenv().CONFIG.CommunityUrl) end
end})
Window:SelectTab("Home")
Window:Open()
