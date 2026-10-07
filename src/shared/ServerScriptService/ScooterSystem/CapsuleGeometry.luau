-- Works out where a character's feet actually belong inside a capsule, by
-- measuring the build instead of trusting a hand-placed attachment. This is the
-- fix for the "stuck in the roof" bug: the old code used a fixed +3 offset from
-- a trigger part that had no relationship to the real floor.

local CapsuleGeometry = {}

-- Ray down through the capsule interior, hitting only that capsule's own parts,
-- and return the Y of the floor's top face.
function CapsuleGeometry.FindFloorY(triggerPart, capsuleModel)
	if not capsuleModel then return nil end

	local parts = {}
	for _, d in ipairs(capsuleModel:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts

	-- start at the capsule's vertical centre (inside the box) and cast down
	local origin = triggerPart.Position
	local hit = workspace:Raycast(origin, Vector3.new(0, -25, 0), params)
	return hit and hit.Position.Y or nil
end

-- Distance from a character's feet to its HumanoidRootPart centre.
-- Derived per-character so R6, R15 and scaled avatars all sit correctly.
function CapsuleGeometry.FeetToRoot(character)
	local hum  = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return 3.0 end
	return hum.HipHeight + (root.Size.Y / 2)
end

-- The CFrame to pivot a character to so it stands on the capsule floor.
function CapsuleGeometry.StandCFrame(character, triggerPart, floorY)
	local lift = CapsuleGeometry.FeetToRoot(character) + 0.15   -- tiny clearance
	local p = triggerPart.Position
	return CFrame.new(p.X, (floorY or p.Y) + lift, p.Z)
end

return CapsuleGeometry
