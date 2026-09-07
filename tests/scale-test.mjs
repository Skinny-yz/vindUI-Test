import fs from 'node:fs';
import {LuauState} from 'luau-web';
const source=fs.readFileSync('core.luau','utf8');
const fn=source.slice(source.indexOf('local function ComputeUIScale()'),source.indexOf('local GlobalScale ='));
const code=`local NullUI={_MobileDesignWidth=640,_MobileDesignHeight=455}
local IsMobileDevice=true
local view={X=0,Y=0}
local function ViewportSize() return view end
${fn}
for _, pair in ipairs({{800,360},{960,540},{1280,720},{2048,922},{2400,1080},{667,375}}) do
 view={X=pair[1],Y=pair[2]}
 local scale=ComputeUIScale()
 assert(640*scale <= view.X-32+0.001)
 assert(455*scale <= view.Y-24+0.001)
 assert(math.abs((640*scale)/(455*scale)-640/455)<0.000001)
end
view={X=1280,Y=720}
local initial=ComputeUIScale()
NullUI._MobileReferenceHeight=900
assert(ComputeUIScale()<initial)
return 'PASS: six landscape viewports, preserved aspect ratio, screen bounds, reference adjustment'`;
const state=await LuauState.createAsync();
try {console.log(await state.loadstring(code,'mobile-scale',true)());} finally {state.destroy();}
