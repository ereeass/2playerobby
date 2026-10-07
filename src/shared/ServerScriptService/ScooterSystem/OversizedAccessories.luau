--=====================================================================
-- OversizedAccessories   (ScooterSystem, server)
--
-- Keeps huge accessories (giant hats, wings, back and shoulder items) from spoiling the
-- two-player scooter: while a player RIDES, any accessory past Shared.Config.
-- OversizedAccessories' limits is hidden, and it comes back the moment they get off.
-- Everything else about their avatar stays exactly as it is - normal hats, hair, faces and
-- clothing are never touched.
--
--   When      RiderAttach calls Hide as a rider is welded on (Driver or Motor, every ride,
--             every revive) and Restore as they are let go. A character that dies is
--             replaced by a fresh one, so nothing is ever carried over.
--   Oversized its Handle's longest side is over MaxSize, or its furthest corner sticks
--             out more than MaxReach from the HumanoidRootPart - both in studs for a
--             normal-size avatar, scaled by the avatar's own BodyHeightScale. Layered
--             clothing (a WrapLayer) gets LayeredAllowance times the room: it wraps the body.
--   Hidden    only if Config HideOversized is true (it is off: oversized accessories stay
--             visible and are just harmless, see Touching). When on, every part of the
--             accessory is made fully transparent (its decals/textures too), the old values
--             remembered and put back on Restore. Nothing is deleted, moved or re-welded, so
--             the rider's pose, the Driver/Motor holds and animations are untouched. Seen the
--             same by everyone (it is done on the server).
--   Physics   a rider is in the ScooterRider collision group (collides with nothing) and
--             massless for the whole ride (RiderAttach), accessories included.
--   Touching  while riding, NO accessory (hidden or not) sets off anything: every accessory
--             part has CanTouch/CanQuery off for the ride, so the laser gates, kill zones and
--             other touch hazards judge only the scooter and the riders' bodies - a huge (or
--             hidden) hat or pair of wings can't clip a laser and kill the duo. An accessory
--             that finishes loading mid-ride is switched off the same way as it arrives. Put
--             back with the rest on Restore.
--   Never     saved, sent to their Roblox avatar, or anything outside this server's copy
--             of their character.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Config"))

local OversizedAccessories = {}

-- what a rider whose avatar had something hidden is told (the red notice at the bottom)
OversizedAccessories.NOTICE = "Some parts of your avatar have been removed due to being too large."

-- true if Hide hid anything (so the rider is told)
function OversizedAccessories.HidAny(saved)
	return saved ~= nil and next(saved.Transparency or {}) ~= nil
end

local function settings()
	return Config.OversizedAccessories or {}
end

-- the avatar's size relative to a normal one
local function scaleOf(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local v = hum and hum:FindFirstChild("BodyHeightScale")
	return (v and v:IsA("NumberValue") and v.Value > 0) and v.Value or 1
end

-- is this accessory too big for the scooter?
function OversizedAccessories.IsOversized(accessory, root, scale)
	local s = settings()
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then return false end
	local room = scale * (handle:FindFirstChildOfClass("WrapLayer") and (s.LayeredAllowance or 1.5) or 1)
	local size = handle.Size
	if math.max(size.X, size.Y, size.Z) > (s.MaxSize or 4.5) * room then return true end
	if root then
		local half, far = size / 2, 0
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local corner = handle.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					far = math.max(far, (corner - root.Position).Magnitude)
				end
			end
		end
		if far > (s.MaxReach or 4.5) * room then return true end
	end
	return false
end

-- For the ride: the character's oversized accessories hidden, and no accessory able to touch
-- anything. Returns what to hand back to Restore.
function OversizedAccessories.Hide(char)
	if not char or settings().Enabled == false then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	local scale = scaleOf(char)
	local saved = { Transparency = {}, Touch = {} }
	local hide = settings().HideOversized == true
	for _, accessory in ipairs(char:GetChildren()) do
		if accessory:IsA("Accessory") then
			local big = hide and OversizedAccessories.IsOversized(accessory, root, scale)
			for _, d in ipairs(accessory:GetDescendants()) do
				if d:IsA("BasePart") then
					saved.Touch[d] = { d.CanTouch, d.CanQuery }
					d.CanTouch, d.CanQuery = false, false
				end
				if big and (d:IsA("BasePart") or d:IsA("Decal")) and d.Transparency < 1 then
					saved.Transparency[d] = d.Transparency
					d.Transparency = 1
				end
			end
		end
	end
	-- accessory parts that load in after this (a first join may still be putting them on)
	-- can't touch anything either
	saved.Conn = char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d:FindFirstAncestorOfClass("Accessory") and not saved.Touch[d] then
			saved.Touch[d] = { d.CanTouch, d.CanQuery }
			d.CanTouch, d.CanQuery = false, false
		end
	end)
	return saved
end

-- Puts back what Hide changed (only on a character still in the game)
function OversizedAccessories.Restore(saved)
	if not saved then return end
	if saved.Conn then saved.Conn:Disconnect() saved.Conn = nil end
	for d, was in pairs(saved.Transparency or {}) do
		if d.Parent then d.Transparency = was end
	end
	for d, was in pairs(saved.Touch or {}) do
		if d.Parent then d.CanTouch, d.CanQuery = was[1], was[2] end
	end
end

return OversizedAccessories
