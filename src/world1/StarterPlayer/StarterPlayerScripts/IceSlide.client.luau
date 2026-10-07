-- Icy surfaces (parts tagged "IcySurface", e.g. the Icy Platform's top): while the scooter
-- this player drives is on one, its movement across the ground lags a little behind where
-- the wheels are taking it - turns drift a touch wide, braking takes a bit longer. Only
-- matters on the driver's machine (it simulates the scooter); anywhere else nothing changes.
-- GRIP: how quickly it catches up with the wheels each frame (1 = no ice, lower = slippier).

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local GRIP = 0.2    -- with the IceTop parts' friction 0.4: full-lock turns ~2x wider, stops ~30% longer than normal road
local TAG  = "IcySurface"

local player = Players.LocalPlayer
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local function refresh() params.FilterDescendantsInstances = CollectionService:GetTagged(TAG) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(refresh)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(refresh)
refresh()

-- the chassis this player DRIVES (the Passenger's machine does not simulate it, so
-- writing its velocity there would only make it jitter on the Passenger's screen)
local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	if not weld then return nil end
	local role = weld:GetAttribute("Role")
	if role ~= nil and role ~= "Driver" then return nil end
	return weld.Part0
end

local carried
RunService.PreSimulation:Connect(function(dt)
	local chassis = myChassis()
	if not chassis then carried = nil return end
	local onIce = workspace:Raycast(chassis.Position, Vector3.new(0, -4, 0), params) ~= nil
	local v = chassis.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	if not onIce then carried = flat return end
	carried = carried or flat
	local a = 1 - (1 - GRIP) ^ (dt * 60)
	carried = carried + (flat - carried) * a
	chassis.AssemblyLinearVelocity = Vector3.new(carried.X, v.Y, carried.Z)
end)
