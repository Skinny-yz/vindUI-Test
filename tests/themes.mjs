import {LuauState} from 'luau-web';
import fs from 'node:fs';
for(const file of ['core.luau','full.luau']){
const source=fs.readFileSync('tests/mock.luau','utf8')+`
-- Model Color3 identity, value type and interpolation for theme testing.
local function color(r,g,b)
 local c={R=r,G=g,B=b,_type='Color3'}
 c.Lerp=function(self,other,t)return color(self.R+(other.R-self.R)*t,self.G+(other.G-self.G)*t,self.B+(other.B-self.B)*t)end
 c.ToHex=function()return 'FFFFFF'end;c.ToHSV=function()return 0,0,1 end
 return c
end
Color3.new=color;Color3.fromRGB=function(r,g,b)return color(r/255,g/255,b/255)end
local UI=(function()
${fs.readFileSync(file,'utf8')}
end)()
local window=UI:CreateWindow({Title='Themes',UseBlur=false})
local tab=window:AddTab('Controls')
local on=tab:AddToggle({Text='On',Default=true})
local off=tab:AddToggle({Text='Off',Default=false})
local slider=tab:AddSlider({Text='Slider',Default=25})
local textbox=tab:AddTextbox({Text='Text'})
local dropdown=tab:AddDropdown({Text='Dropdown',Options={'A','B'},Default='A'})
local function switch(api)
 for _,child in ipairs(api.Instance:GetChildren())do if child.Size and child.Size.X.Offset==40 and child.Size.Y.Offset==22 then return child end end
 error('Switch missing')
end
local function knob(sw)
 for _,child in ipairs(sw:GetChildren())do if child.ClassName=='Frame' and child.Size.X.Offset==16 then return child end end
 error('Knob missing')
end
local context
UI:Use({Name='theme-test',API=1,Install=function(c)context=c end})
local probe=Instance.new('Frame');probe.Parent=UI._Root
context.BindTheme(probe,'BackgroundColor3','Text')
-- Selection must keep Accent identity when Dark Text and Accent happen to match.
context.Tween(probe,{BackgroundColor3=context.ThemeValue('Accent')},.2)
UI:Notify({Title='Theme notification',Text='Theme body',Type='success'})
local notificationTitle
for _,object in ipairs(UI._Root:GetDescendants())do if object.ClassName=='TextLabel' and object.Text=='Theme notification' then notificationTitle=object end end
assert(notificationTitle)
if UI:HasModule('chat-common') then
 window:AddChatPanel({Title='Theme chat'})
 window:AddCloudPanel({Title='Theme cloud'})
end
local intro=UI:ShowIntro({AutoClose=false,UseBlur=false})
local card=intro.Instance:FindFirstChild('Anchor'):FindFirstChild('IntroCard')
for _,name in ipairs({'Midnight','Forest','Light','Dark','Midnight'})do
 UI:SetTheme(name)
 assert(switch(on).BackgroundColor3==UI.Theme.ToggleOn,name..' on track')
 assert(knob(switch(on)).BackgroundColor3==UI.Theme.ToggleKnobOn,name..' on knob')
 assert(switch(off).BackgroundColor3==UI.Theme.ToggleOff,name..' off track')
 assert(knob(switch(off)).BackgroundColor3==UI.Theme.ToggleKnob,name..' off knob')
 assert(on.Instance.BackgroundColor3==UI.Theme.Card,name..' card')
 assert(window._gui.BackgroundColor3==UI.Theme.Background,name..' window')
 assert(notificationTitle.TextColor3==UI.Theme.Text,name..' existing notification')
 assert(probe.BackgroundColor3==UI.Theme.Accent,name..' active token')
 assert(card.BackgroundColor3==UI.Theme.Background,name..' intro')
 assert(card:FindFirstChild('Title').TextColor3==UI.Theme.Text,name..' intro text')
 assert(on:Get()==true and off:Get()==false and slider:Get()==25 and dropdown:Get()=='A')
end
on:Set(false,true);UI:SetTheme('Forest');assert(switch(on).BackgroundColor3==UI.Theme.ToggleOff)
on:Set(true,true);UI:SetTheme('Midnight');assert(switch(on).BackgroundColor3==UI.Theme.ToggleOn)
local custom=Color3.fromRGB(200,75,180)
UI:SetTheme({Accent=custom});assert(UI.Theme.ToggleOn==custom and UI.Theme.SliderFill==custom)
local override=Color3.fromRGB(1,2,3)
UI:SetTheme({ToggleOn=override});assert(switch(on).BackgroundColor3==override)
UI:SetTheme('Midnight');assert(switch(on).BackgroundColor3==UI.Theme.Accent)
local newer=tab:AddToggle({Default=true});assert(switch(newer).BackgroundColor3==UI.Theme.ToggleOn)
local customIntro=UI:ShowIntro({UseBlur=false,AutoClose=false,TextColor=override})
UI:SetTheme('Light');assert(customIntro.Instance:FindFirstChild('Anchor'):FindFirstChild('IntroCard'):FindFirstChild('Title').TextColor3==override)
customIntro:Destroy()
return 'PASS ${file}: presets, live toggle states, cards, window, intro, explicit token identity, custom overrides and new controls'
`;
const state=await LuauState.createAsync();try{console.log(await state.loadstring(source,'themes',true)());}finally{state.destroy();}
}

