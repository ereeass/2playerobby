-- Collision groups that keep avatars from affecting the scooter.
--
-- The scooter is moved ONLY by its motor and steering servo. No avatar part - a
-- rider's arms, legs, accessories or tools, or a bystander walking into it - ever
-- touches a scooter part, so nothing can push it, flip it or turn it.
--
--   ScooterBody   every scooter part, the invisible DeckFloor included. Riders are
--                 in PlatformStand (see RiderAttach), so nothing about them needs
--                 to touch the scooter at all.
--   ScooterRider  characters currently riding. They are welded to the scooter, so
--                 anything touching them would push the scooter: they collide with
--                 nothing at all - not the scooter, each other, the world or a
--                 bystander. The scooter's own wheels and deck do the colliding.
--                 (Touch-based obby hazards should therefore detect the scooter.)
--   Characters    every other player character. They walk straight through each other
--                 (no bumping or pushing in the lobby), but still stand on the world.
--
-- Scooters also pass through each other: another team's scooter (and its riders) is
-- a ghost you drive straight through, and it fades on each client when it is close
-- (StarterPlayerScripts.ScooterGhostFx).
-- Everything else keeps its normal collisions: scooters still hit the world, and
-- characters still collide with the world.

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	Body      = "ScooterBody",
	Rider     = "ScooterRider",
	Character = "Characters",
}

local ATTR = "ScooterCollisionGroup"

local registered = false
function CollisionGroups.Ensure()
	if registered then return end
	for _, g in ipairs({ CollisionGroups.Body, CollisionGroups.Rider, CollisionGroups.Character }) do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	local function off(a, b) PhysicsService:CollisionGroupSetCollidable(a, b, false) end
	off(CollisionGroups.Rider, CollisionGroups.Rider)
	off(CollisionGroups.Rider, CollisionGroups.Body)
	off(CollisionGroups.Rider, "Default")
	off(CollisionGroups.Rider, CollisionGroups.Character)
	off(CollisionGroups.Character, CollisionGroups.Body)
	off(CollisionGroups.Character, CollisionGroups.Character)   -- players walk through each other
	off(CollisionGroups.Body, CollisionGroups.Body)
	registered = true
end

-- Every part of a scooter. Done at spawn as well as in the template, so a swapped
-- or re-skinned model can never slip back into Default.
function CollisionGroups.TagScooter(model)
	CollisionGroups.Ensure()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = CollisionGroups.Body end
	end
end

-- Parts that arrive after the character spawned (accessories that finish loading,
-- an equipped tool) join whatever group the character is currently in.
local hooked = setmetatable({}, { __mode = "k" })

function CollisionGroups.SetCharacterGroup(char, group)
	if not char then return end
	CollisionGroups.Ensure()
	char:SetAttribute(ATTR, group)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = group end
	end
	if not hooked[char] then
		hooked[char] = true
		char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = char:GetAttribute(ATTR) or CollisionGroups.Character
			end
		end)
	end
end

-- Every player character starts as a bystander.
function CollisionGroups.TrackCharacter(char)
	CollisionGroups.SetCharacterGroup(char, CollisionGroups.Character)
end

return CollisionGroups
