import {LuauState} from 'luau-web';
import fs from 'node:fs';
const root='./';
const wrap=f=>`(function()\n${fs.readFileSync(root+f,'utf8')}\nend)()`;
const test=fs.readFileSync('tests/mock.luau','utf8')+`
local UI = ${wrap('core.luau')}
assert(UI.AddSpotifyPanel == nil)
assert(UI.CreateAIAssistant == nil)
local window = UI:CreateWindow({Title='Test', Size=UDim2.fromOffset(640,455), UseBlur=false})
assert(window._gui.Size.X.Offset == 640 and window._gui.Size.Y.Offset == 455)
assert(window._UserInfoFrame.Visible)
window:SetUserInfo({Avatar='12345',NameMode='anonymous'})
assert(window._UserAvatar.Image=='rbxassetid://12345')
assert(window._UserName.Text=='Anônimo' and not window._UserHandle.Visible)
local button=window:AddDockButton({Icon='music'})
assert(not window._UserInfoFrame.Visible)
button.Instance.Visible=false
window:_RefreshFooter()
assert(window._UserInfoFrame.Visible)
UI:SetDensity('compact');assert(UI:GetDensity()=='compact')
window:ResetLayout()
local tab=window:AddTab('Test')
local first=tab:AddSlider({Text='Slider',Default=0})
local second=tab:AddSlider({Text='Slider 2',Default=0})
local function hitbox(api) for _,child in ipairs(api.Instance:GetDescendants()) do if child.Name=='SliderHitBox' then return child end end end
local finger={UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(320,0)}
hitbox(first).InputBegan:Fire(finger)
hitbox(second).InputBegan:Fire(finger)
assert(first:Get()>0 and second:Get()==0,'one gesture must not capture two sliders')
game:GetService('UserInputService').InputEnded:Fire(finger)
hitbox(second).InputBegan:Fire(finger)
assert(second:Get()>0,'slider ownership must release')
game:GetService('UserInputService').InputEnded:Fire(finger)
tab:AddTextbox({Text='Textbox'})
tab:AddDropdown({Text='Dropdown',Options={'A','B'}})
tab:AddColorPicker({Text='Color'})
window:AddUIPreferences()
window:ShowNotificationHistory()
local assistant=${wrap('modules/assistant.luau')}
assert(not pcall(function() UI:Use(assistant) end))
UI:Use(${wrap('modules/chat-common.luau')})
UI:Use(assistant)
UI:Use(assistant)
UI:Use(${wrap('modules/cloud.luau')})
UI:Use(${wrap('modules/spotify.luau')})
UI:Use(${wrap('modules/feedback.luau')})
assert(UI:HasModule('assistant') and UI:HasModule('cloud'))
window:AddChatPanel({Title='Assistant'})
window:AddGlobalChatPanel({Title='Global'})
window:AddCloudPanel({Title='Cloud'})
window:AddSpotifyPanel({Title='Music'})
UI:CreateAIAssistant({Window=window,Providers={}})
UI:CloudService({})
return 'PASS: core, profile, density, reset, controls, preferences, module dependencies, chat constructors, optional services'
`;

const state=await LuauState.createAsync();
try {console.log(await state.loadstring(test,'smoke',true)());} finally {state.destroy();}
