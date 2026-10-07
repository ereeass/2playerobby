-- Floats the balloon house: a slow bob and a gentle sway.
local RunService = game:GetService("RunService")
local model = script.Parent
local home = model:GetPivot()
local BOB, BOB_TIME = 1, 6
local SWAY, SWAY_TIME = 2, 8
local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local t = os.clock() - t0
	local y = math.sin(t / BOB_TIME * math.pi * 2) * BOB
	local a = math.rad(math.sin(t / SWAY_TIME * math.pi * 2) * SWAY)
	local b = math.rad(math.cos(t / (SWAY_TIME * 1.4) * math.pi * 2) * SWAY * 0.5)
	model:PivotTo(home * CFrame.new(0, y, 0) * CFrame.Angles(b, 0, a))
end)
