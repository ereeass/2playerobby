-- Cones on the roads that a scooter knocks flying. Every Model tagged "KnockableCone"
-- (copy one anywhere, the tag goes with it).
--
-- Standing cones don't block scooters: they're in the "Cones" collision group, which
-- scooters pass through. The knocking-over is done on the riders' own machines
-- (StarterPlayerScripts.ConeKnock): only the two riders who hit a cone see it fly,
-- everyone else sees it standing where it was. After 10 seconds it's back for them too.
-- This script only sets up the collision groups and puts every tagged cone in its group.

local CollectionService = game:GetService("CollectionService")
local PhysicsService    = game:GetService("PhysicsService")

local TAG = "KnockableCone"

local function register(g)
	if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end
end
for _, g in ipairs({ "ScooterBody", "ScooterRider", "Characters", "Cones", "KnockedCone" }) do register(g) end
-- standing cones: scooters drive through them (and knock them over locally)
PhysicsService:CollisionGroupSetCollidable("Cones", "ScooterBody", false)
-- a knocked cone flying about: hits the road and other cones, never a scooter or a person
for _, g in ipairs({ "ScooterBody", "ScooterRider", "Characters" }) do
	PhysicsService:CollisionGroupSetCollidable("KnockedCone", g, false)
end

local function setup(cone)
	for _, p in ipairs(cone:GetDescendants()) do
		if p:IsA("BasePart") then p.CollisionGroup = "Cones" end
	end
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(setup)
for _, cone in ipairs(CollectionService:GetTagged(TAG)) do setup(cone) end
