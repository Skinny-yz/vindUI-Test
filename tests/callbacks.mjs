import {LuauState} from 'luau-web';
import fs from 'node:fs';

for (const file of ['core.luau', 'full.luau']) {
  const test = fs.readFileSync('tests/mock.luau', 'utf8') + `
local UI = (function()
${fs.readFileSync(file, 'utf8')}
end)()
local window = UI:CreateWindow({Title = 'Callbacks', UseBlur = false})
local tab = window:AddTab('Callbacks')
local notices, warnings, threads = {}, {}, {}
UI.Notify = function(_, opts) table.insert(notices, opts) end
warn = function(message) table.insert(warnings, message) end
task.spawn = function(fn, ...)
 local co = coroutine.create(fn)
 local ok, err = coroutine.resume(co, ...)
 assert(ok, tostring(err))
 table.insert(threads, co)
 return co
end
local function fail() error('expected callback failure') end
local button = tab:AddButton({Text = 'Fail', Callback = fail})
button.Instance:FindFirstChildOfClass('TextButton').MouseButton1Click:Fire()
assert(#notices == 1 and notices[1].Title == 'Callback Error')
assert(notices[1].Type == 'error' and string.find(notices[1].Text, 'expected callback failure'))
assert(#warnings == 1 and string.find(warnings[1], 'expected callback failure'))
local received
local toggle = tab:AddToggle({Callback = function(value) received = value; fail() end})
local healthyListener = 0
toggle:OnChanged(fail)
local connection = toggle:OnChanged(function(value) assert(value == true); healthyListener += 1 end)
toggle:Set(true)
assert(received == true and healthyListener == 1 and #notices == 3)
connection:Disconnect()
toggle:Set(false, true)
assert(#notices == 3 and healthyListener == 1)
local number = tab:AddSlider({Min = 0, Max = 10, Callback = fail})
number:OnChanged(fail)
number:OnChanged(function(value) received = value end)
number:Set(4)
assert(received == 4 and #notices == 5)
number:Set(7, true)
assert(#notices == 5 and received == 4)
local group = tab:AddButtonGroup({Buttons = {{Text = 'Index', Callback = function(index) assert(index == 1); received = index end}}})
group.Buttons[1].Instance.Activated:Fire()
assert(received == 1 and #notices == 5)
-- Independently exercise the production helper with trailing nil arguments and yielding.
local NullUI = UI
local SpawnCallback = (function()
${fs.readFileSync(file, 'utf8').match(/local function SpawnCallback\(callback, \.\.\.\)[\s\S]*?(?=\nlocal function MakeSignal)/)[0]}
return SpawnCallback
end)()
SpawnCallback(function(...)
 local args = table.pack(...)
 assert(args.n == 4 and args[1] == 1 and args[2] == nil and args[3] == 3 and args[4] == nil)
end, 1, nil, 3, nil)
local co = SpawnCallback(function() coroutine.yield(); error('after yielding') end)
assert(coroutine.status(co) == 'suspended')
local ok, err = coroutine.resume(co)
assert(ok, tostring(err))
assert(#notices == 6 and string.find(notices[6].Text, 'after yielding'))
UI.Notify = function() error('renderer failure') end
SpawnCallback(fail)
assert(string.find(warnings[#warnings], 'Could not show callback error'))
return 'PASS ${file}: error notifications, listener isolation, silent updates, arguments, yielding, renderer failure'
`;
  const state = await LuauState.createAsync();
  try { console.log(await state.loadstring(test, 'callbacks', true)()); }
  finally { state.destroy(); }
}
