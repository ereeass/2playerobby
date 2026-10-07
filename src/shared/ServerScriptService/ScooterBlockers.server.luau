-- Invisible "ScooterBlocker" parts (tagged ScooterBlocker, e.g. the ScooterBumper on each of
-- Road3's fallen logs) stop scooters only: they're a bit taller than what they sit on, so a
-- scooter can't ride up onto it, while players, props and everything else pass through.
-- This keeps the ScooterBlocker collision group colliding with ScooterBody and nothing else.
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local function setup()
	for _, g in ipairs({ "ScooterBody", "ScooterBlocker" }) do
		if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end
	end
	for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		PhysicsService:CollisionGroupSetCollidable("ScooterBlocker", g.name, g.name == "ScooterBody")
	end
end
local function tagged(p)
	if p:IsA("BasePart") then p.CollisionGroup = "ScooterBlocker" end
end
pcall(setup)
for _, p in ipairs(CollectionService:GetTagged("ScooterBlocker")) do tagged(p) end
CollectionService:GetInstanceAddedSignal("ScooterBlocker"):Connect(tagged)
task.delay(5, function() pcall(setup) end)   -- groups other scripts register at startup
