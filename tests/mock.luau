local function Signal()
 local callbacks={}
 return {Connect=function(_,fn)local entry={fn=fn};table.insert(callbacks,entry);return {Disconnect=function()entry.fn=nil end}end,Wait=function()end,Fire=function(_,...)for _,entry in ipairs(callbacks)do if entry.fn then entry.fn(...)end end end}
end
local mt={}
local function vec(x,y,z)return setmetatable({X=x or 0,Y=y or 0,Z=z or 0,_type="Vector2"},mt)end
mt.__add=function(a,b)return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
mt.__sub=function(a,b)return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
mt.__mul=function(a,b)if type(a)=="number"then a,b=b,a end;return vec(a.X*b,a.Y*b,a.Z*b)end
mt.__div=function(a,b)return vec(a.X/b,a.Y/b,a.Z/b)end
mt.__index=function(a,k)if k=="Magnitude"then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z)elseif k=="Lerp"then return function(a,b,t)return a+(b-a)*t end end end
Vector2={new=vec,zero=vec()};Vector3={new=vec,zero=vec()}
UDim={new=function(s,o)return {Scale=s or 0,Offset=o or 0}end}
UDim2={new=function(a,b,c,d)return {X=UDim.new(a,b),Y=UDim.new(c,d)}end}
UDim2.fromOffset=function(a,b)return UDim2.new(0,a,0,b)end
UDim2.fromScale=function(a,b)return UDim2.new(a,0,b,0)end
local function color(r,g,b)local c={R=r,G=g,B=b};c.Lerp=function()return c end;c.ToHex=function()return "FFFFFF"end;c.ToHSV=function()return 0,0,1 end;return c end
Color3={new=color,fromRGB=function(r,g,b)return color(r/255,g/255,b/255)end,fromHSV=function()return color(1,0,0)end,toHSV=function()return 0,0,1 end,fromHex=function()return color(1,1,1)end}
local seq={new=function(...)return {...}end}
ColorSequence=seq;ColorSequenceKeypoint=seq;NumberSequence=seq;NumberSequenceKeypoint=seq;TweenInfo=seq;Rect=seq
Enum=setmetatable({}, {__index=function(t,k)local e=setmetatable({}, {__index=function(u,n)local v={Name=n};rawset(u,n,v);return v end});rawset(t,k,e);return e end})
Font={new=function(...)return {...}end,fromEnum=function(...)return {...}end}
CFrame={new=function()return {Position=vec(),XVector=vec(1),YVector=vec(0,1),ZVector=vec(0,0,1)}end,fromMatrix=function()return {}end}
local function object(class)
 local p={ClassName=class,Name=class,Visible=true,AbsoluteSize=vec(640,455),AbsolutePosition=vec(),AbsoluteWindowSize=vec(640,455),AbsoluteCanvasSize=vec(640,455),AbsoluteContentSize=vec(400,60),Position=UDim2.fromOffset(0,0),Size=UDim2.fromOffset(100,40),AnchorPoint=vec(),CanvasPosition=vec(),ZIndex=1,Scale=1,Text="",BackgroundTransparency=0}
 local kids,signals,attrs={},{},{}
 local o
 local methods={
 GetChildren=function()return table.clone(kids)end,
 GetDescendants=function()local r={};for _,k in ipairs(kids)do table.insert(r,k);for _,d in ipairs(k:GetDescendants())do table.insert(r,d)end end;return r end,
 FindFirstChild=function(_,name)for _,k in ipairs(kids)do if k.Name==name then return k end end end,
 FindFirstChildOfClass=function(_,name)for _,k in ipairs(kids)do if k.ClassName==name then return k end end end,
 GetPropertyChangedSignal=function(_,key)signals[key]=signals[key] or Signal();return signals[key]end,
 IsA=function(_,name)return name==class or (name=="GuiButton" and (class=="TextButton" or class=="ImageButton")) or (name=="GuiObject" and (class=="Frame" or class=="CanvasGroup" or class=="ScrollingFrame" or class=="TextLabel" or class=="TextBox" or class=="ImageLabel" or class=="ImageButton" or class=="TextButton"))end,
 SetAttribute=function(_,key,v)attrs[key]=v end,GetAttribute=function(_,key)return attrs[key]end,
 IsFocused=function()return false end,CaptureFocus=function()end,ReleaseFocus=function()end,
 }
 methods.FindFirstChildWhichIsA=methods.FindFirstChildOfClass
 methods.Destroy=function()p.Parent=nil end
 methods.Clone=function()local n=object(class);for k,v in pairs(p)do if k~="Parent" then n[k]=v end end;return n end
 methods.WaitForChild=function(_,name)local found=methods.FindFirstChild(nil,name);if found then return found end;local n=object(name);n.Parent=o;return n end
 o=setmetatable({_type="Instance",_children=kids},{__index=function(_,k)
 if methods[k]then return methods[k]end
 if p[k]~=nil then return p[k]end
 if k:find("Changed")or k:find("Input")or k:find("Mouse")or k=="Destroying"or k=="Activated"or k=="Focused"or k=="FocusLost"or k=="ChildRemoved"or k=="ChildAdded"or k=="Heartbeat"or k=="RenderStepped"or k=="WindowFocusReleased"then signals[k]=signals[k]or Signal();return signals[k]end
 end,__newindex=function(_,k,v)p[k]=v;if k=="Parent"and v then table.insert(v._children,o)end end})
 return o
end
Instance={new=object}
local realtype=type
typeof=function(x)return realtype(x)=="table"and x._type or realtype(x)end
local services={}
game={GetService=function(_,name)if not services[name]then services[name]=object(name)end;return services[name]end,HttpGet=function()error("HTTP disabled in test")end,PlaceId=1,JobId="test"}
local player=object("Player");player.Name="TestUser";player.DisplayName="Test Display";player.UserId=123
player.PlayerGui=object("PlayerGui");player.PlayerGui.Parent=player
local players=game:GetService("Players");players.LocalPlayer=player;players.GetPlayers=function()return {player}end;players.GetUserThumbnailAsync=function()return "rbxassetid://123",true end
local input=game:GetService("UserInputService");input.TouchEnabled=true;input.MouseEnabled=false;input.GetFocusedTextBox=function()return nil end
local gui=game:GetService("GuiService");gui.GetGuiInset=function()return vec(0,24),vec()end
local http=game:GetService("HttpService");http.GenerateGUID=function()return "test-guid"end;http.JSONEncode=function()return "{}"end;http.JSONDecode=function()return {}end
local tween=game:GetService("TweenService");tween.Create=function(_,target,info,props)return {Play=function()for k,v in pairs(props)do target[k]=v end end,Cancel=function()end,Completed=Signal()}end
local text=game:GetService("TextService");text.GetTextSize=function(_,str,size,font,bounds)return vec(math.min(#str*size/2,bounds.X),size)end
workspace=object("Workspace");workspace.CurrentCamera=object("Camera");workspace.CurrentCamera.ViewportSize=vec(1000,500);workspace.CurrentCamera.CFrame=CFrame.new()
workspace.CurrentCamera.ScreenPointToRay=function(_,x,y)return {Origin=vec(x/1000,y/1000),Direction=vec(0,0,-1)}end
workspace.CurrentCamera.GetRenderCFrame=function()return CFrame.new()end
task={spawn=function()end,defer=function()end,delay=function()end,wait=function()end}
warn=function()end
getgenv=function()return {}end
