-- Copy this package to VindUI/ in your script environment.
local function loadFile(path)
    return assert(loadstring(readfile("VindUI/" .. path)))()
end

local UI = loadFile("core.luau")
local CONFIG = {
    Spotify = false,
    Cloud = false,
    SpotifyBridgeUrl = "",
    CloudBaseUrl = "",
}

if CONFIG.Spotify then UI:Use(loadFile("modules/spotify.luau")) end
if CONFIG.Cloud then
    UI:Use(loadFile("modules/chat-common.luau"))
    UI:Use(loadFile("modules/cloud.luau"))
end

local Window = UI:CreateWindow({
    Title = "Vind UI",
    Subtitle = "Modular",
    Size = UDim2.fromOffset(640, 455),
    UserInfo = {Avatar = "player", NameMode = "display"},
})
local Home = Window:AddTab("Home")
Home:AddParagraph({Title = "Interface pronta", Text = "As integrações só são registradas quando ativadas no CONFIG."})
Home:AddSlider({Text = "Volume", Min = 0, Max = 100, Default = 50})
Home:AddSlider({Text = "Brilho", Min = 0, Max = 100, Default = 50})
Window:AddUIPreferences()

if CONFIG.Spotify then
    Window:AddSpotifyPanel({BridgeUrl = CONFIG.SpotifyBridgeUrl})
end
if CONFIG.Cloud then
    local Service = UI:CloudService({BaseUrl = CONFIG.CloudBaseUrl, Script = "my-script"})
    local Panel = Window:AddCloudPanel({Service = Service})
    Window:AddDockButton({Icon = "cloud", Callback = function() Panel:Toggle() end})
end
