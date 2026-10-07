-- Floats the balloon gently: a slow bob up and down and a little sway.
local RunService = game:GetService("RunService")
local model = script.Parent
local home = model:GetPivot()
local BOB, BOB_TIME = 0.8, 5        -- studs up/down, seconds per bob
local SWAY, SWAY_TIME = 2.5, 7      -- degrees of sway, seconds per sway
local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local t = os.clock() - t0
	local y = math.sin(t / BOB_TIME * math.pi * 2) * BOB
	local a = math.rad(math.sin(t / SWAY_TIME * math.pi * 2) * SWAY)
	local b = math.rad(math.cos(t / (SWAY_TIME * 1.3) * math.pi * 2) * SWAY * 0.6)
	model:PivotTo(home * CFrame.new(0, y, 0) * CFrame.Angles(b, 0, a))
end)
