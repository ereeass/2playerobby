-- JoinDeviceReport: tells the server (JoinWebhook) what kind of device this player is on and
-- their screen size, once, for the join message in Discord. Nothing else is sent.
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
-- Nothing on the server listens for this any more (no JoinDeviceInfo in either world), so it
-- only reports if that remote is there: a quick look, then it stops - no long wait.
local remote = game:GetService("ReplicatedStorage"):WaitForChild("JoinDeviceInfo", 5)
if not remote then return end
local cam = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() and workspace.CurrentCamera
task.wait(1)   -- the viewport has its real size by now
local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
local kind
if UIS.VREnabled then kind = "VR"
elseif GuiService:IsTenFootInterface() then kind = "Console"
elseif UIS.TouchEnabled and not UIS.KeyboardEnabled then
	kind = (math.min(vp.X, vp.Y) >= 600) and "Tablet" or "Phone"
else kind = "PC" end
remote:FireServer({ kind = kind, w = math.floor(vp.X), h = math.floor(vp.Y) })
