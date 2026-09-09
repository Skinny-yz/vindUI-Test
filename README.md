# New elements

Replace core.luau / full.luau in your distribution. example.luau loads full.luau from the existing GitHub URL.

All value controls accept Text, Description, Default, Flag and Callback(value). Use :Get(), :Set(value, silent), :OnChanged(callback), :Destroy(). A Flag includes the value in GetConfig / SaveConfig / CopyConfigJSON.

| Method | Options / value |
| --- | --- |
| AddSegmentedControl | Options = {"Normal", "Fast"}; string value; animated selection, wraps in narrow spaces |
| AddRangeSlider | Min, Max, Step; Default = {20, 80}; two handles and editable numeric endpoints |
| AddNumberInput | Min, Max, Step; numeric value; minus/plus and direct input |
| AddListEditor | Default = {"Alpha", "Beta"}; string array; :Add(text), :Remove(index) |
| AddRadioGroup | Options; one selected string |
| AddCheckboxGroup | Options; array of selected strings |
| AddProgressBar | Min, Max, Default; optional Label; :Set(number) |
| AddImageCard | Title, Description, Image, Height, Actions (Button Group definitions); :SetImage(asset) and :Destroy() |
| AddMultiLineTextbox | Height, Placeholder, Default; scrollable multiline text; commits on focus loss |

`local ok, result, fallbackJSON = VindUI:CopyConfigJSON()`

Success returns true and the copied JSON string. Clipboard failure returns false, an error message, and JSON when encoding succeeded. No configuration is sent to a server.

Example usage includes a New Elements tab with all additions, a working progress demo and a copy-config button. Existing UI and independent notification scale are preserved.

Validation: Luau compilation for core/full/example and simulated tests of constructors, bounds, range ordering, selections, config restore, callbacks, clipboard handling and cleanup. Live Roblox rendering has not been verified.
