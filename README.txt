Replace core.luau, full.luau and example.luau. Run the updated example.

Tab boxes:
local box = tab:AddTabBox()
local main = box:AddTab("Main")
local settings = box:AddTab("Settings")
main:AddToggle({Text = "Enable", Default = false})
box:SelectTab("Settings")

Toggle-dependent settings:
local audio = tab:AddToggleSection({Title = "Audio Settings", Text = "Enable Audio", Default = false})
audio:AddSlider({Text = "Volume", Min = 0, Max = 100, Default = 50})
audio:SetEnabled(true) -- optional second argument: silent
-- audio.Toggle exposes the toggle control; audio.Section exposes the collapsible section.
-- Child values are retained when hidden. Hiding settings does not stop application logic;
-- use the parent toggle Callback to enable/disable your actual feature.

The example demonstrates both features under Examples > Sections.
Validated compilation and simulated tab switching, toggle changes (including silent updates), and retained slider values. Visual rendering still requires Roblox testing.
