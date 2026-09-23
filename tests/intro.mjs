import {LuauState} from 'luau-web';
import fs from 'node:fs';
for (const file of ['core.luau', 'full.luau']) {
 const source=fs.readFileSync('tests/mock.luau','utf8')+`
local UI=(function()
${fs.readFileSync(file,'utf8')}
end)()
local heartbeat=game:GetService('RunService').Heartbeat
local calls=0
local reason
-- Activate callbacks without running unrelated startup background loops.
task.spawn=function(fn,...) local co=coroutine.create(fn); local ok,err=coroutine.resume(co,...); assert(ok,tostring(err)); return co end
local disabled=UI:ShowIntro({Enabled=false})
assert(disabled.Instance==nil and disabled:IsFinished())
disabled:Wait():SetProgress(.5):SetStatus('ignored'):Complete():Destroy()
assert(UI._ActiveIntro==nil)
local intro=UI:ShowIntro({Title='Custom',AutoClose=false,OnComplete=function(r) calls+=1;reason=r end})
assert(intro.Instance.Name=='VindIntro' and not intro:IsFinished())
local card=intro.Instance:FindFirstChild('Anchor'):FindFirstChild('IntroCard')
assert(card:FindFirstChild('Title').Text=='Custom')
intro:SetProgress(2,'Loaded');assert(intro:GetProgress()==1 and card:FindFirstChild('Status').Text=='Loaded')
intro:SetProgress(-1);assert(intro:GetProgress()==0)
intro:SetProgress(0/0);assert(intro:GetProgress()==0)
heartbeat:Fire(20);assert(not intro:IsFinished())
workspace.CurrentCamera.ViewportSize=Vector2.new(320,240)
heartbeat:Fire(.01)
local anchor=intro.Instance:FindFirstChild('Anchor')
local fit=anchor:FindFirstChildOfClass('UIScale').Scale
assert(fit*anchor.Size.X.Offset<=288 and fit*anchor.Size.Y.Offset<=208)
intro:Complete('Done'):Complete('Duplicate')
heartbeat:Fire(.2);assert(not intro:IsFinished())
heartbeat:Fire(.3);assert(intro:IsFinished() and calls==1 and reason=='completed' and UI._ActiveIntro==nil)
intro:Destroy();assert(calls==1)
local auto=UI:ShowIntro({Duration=.2,ReducedMotion=true,OnComplete=function()calls+=1 end})
heartbeat:Fire(.1);assert(auto:GetProgress()==.5)
heartbeat:Fire(.1);assert(auto:IsFinished() and calls==2)
local previous=UI:ShowIntro({AutoClose=false,OnComplete=function()calls+=100 end})
local next=UI:ShowIntro({AutoClose=false,ReducedMotion=true,Skippable=true,OnComplete=function(r)reason=r end})
assert(previous:IsFinished())
next.Instance:FindFirstChild('Anchor'):FindFirstChild('IntroCard'):FindFirstChild('Skip').Activated:Fire()
assert(next:IsFinished() and reason=='skipped' and calls==2)
local waiting=UI:ShowIntro({AutoClose=false})
waiting.Instance.Destroying:Fire();assert(waiting:IsFinished())
local unloading=UI:ShowIntro({AutoClose=false})
UI._Root.Destroying:Fire();assert(unloading:IsFinished())
return 'PASS ${file}: optional intro, customization, progress, timing, resize, skip, single completion, replacement and cleanup'
`;
 const state=await LuauState.createAsync();
 try{console.log(await state.loadstring(source,'intro',true)());}finally{state.destroy();}
}
