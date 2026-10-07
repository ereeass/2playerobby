-- Keeps the scooter this player DRIVES off its side while its pitch behaves naturally
-- (ReplicatedStorage.ScooterSystem.Shared.Balance): every frame, before physics. The
-- scooter is simulated by the Driver's machine, so that is the only place this runs; the
-- Passenger's machine leaves the scooter alone.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local Balance = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Balance"))

local player = Players.LocalPlayer
local chassis, follower

-- the chassis this player is welded to, if they are DRIVING it (RiderAttach; a weld from
-- before the Role attribute existed counts as driving, as it always did)
local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	if not weld then return nil end
	local role = weld:GetAttribute("Role")
	if role ~= nil and role ~= "Driver" then return nil end
	return weld.Part0
end

RunService.PreSimulation:Connect(function(dt)
	local now = myChassis()
	if now ~= chassis then
		if follower then follower:Release() end
		chassis, follower = now, nil
	end
	if chassis and not follower then follower = Balance.new(chassis) end
	if follower then follower:Step(dt) end
end)
