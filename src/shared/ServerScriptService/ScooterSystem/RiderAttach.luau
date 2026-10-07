-- Holds a STANDING rider on a scooter.
--
-- The hold is a Weld between the chassis and the character's HumanoidRootPart, so
-- scooter and riders are one rigid body. Nothing here anchors a character,
-- ragdolls a Humanoid, or writes a CFrame on a per-frame loop.
--
-- Riders STAND rather than sit: a Seat would force a sitting pose. The stand
-- attachments therefore mark FOOT height, not root height, and the Humanoid is put
-- in PlatformStand for the ride (see lockMovement) instead of walking on the deck.
--
-- This module only HOLDS the rider. How the body is posed on top of that hold
-- (planted feet, hands on the grips) is RiderPose's job.

local RiderPose       = require(script.Parent:WaitForChild("RiderPose"))
local CollisionGroups = require(script.Parent:WaitForChild("CollisionGroups"))
local OversizedAccessories = require(script.Parent:WaitForChild("OversizedAccessories"))

local RiderAttach = {}

-- Target knee angle while riding (180 = locked straight). The hips are dropped just
-- enough to reach it for THIS avatar's leg lengths, and RiderPose keeps the soles on
-- the deck, so the difference becomes a slight, natural knee bend. Riders are in
-- PlatformStand, so no idle animation adds a pelvis bob on top: this is the bend
-- you get. Ankle limits of ~10 degrees mean a deeper bend tips the toes down, so
-- aim shallow.
local KNEE_ANGLE = 160

local ROLE_ATTACHMENT = {
	Driver    = "DriverPosition",
	Passenger = "PassengerPosition",
}

-- A rider is carried, not walking. PlatformStand is Roblox's own state for a
-- character standing on a moving platform: the Humanoid stops running its walk,
-- jump and stand-up controller, and the Animate script stops playing walk and run.
--
-- Without it the rear rider bounced. That rider is simulated on the DRIVER's
-- machine, so its own client only sees it moving at scooter speed, reports it as
-- Running at up to 20 studs/s, and plays the run cycle - measured: torso bobbing
-- 0.2 studs every time W or S moved the scooter. The driver never showed it only
-- because the driver simulates itself and measures speed against the deck.
--
-- The Humanoid stays alive, keeps its health and events, and is posed entirely by
-- RiderPose's IK. WalkSpeed / jump / AutoRotate are zeroed as well so nothing can
-- fight the hold if PlatformStand is ever cleared by something else.
local function lockMovement(hum)
	local saved = {
		JumpPower     = hum.JumpPower,
		JumpHeight    = hum.JumpHeight,
		WalkSpeed     = hum.WalkSpeed,
		AutoRotate    = hum.AutoRotate,
		PlatformStand = hum.PlatformStand,
	}
	hum.PlatformStand = true
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,  false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum.JumpPower, hum.JumpHeight = 0, 0
	hum.WalkSpeed  = 0
	hum.AutoRotate = false
	return saved
end

local function restoreMovement(hum, saved)
	if not (hum and hum.Parent) then return end
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,  true)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
	hum.JumpPower, hum.JumpHeight = saved.JumpPower, saved.JumpHeight
	hum.WalkSpeed, hum.AutoRotate = saved.WalkSpeed, saved.AutoRotate
	hum.PlatformStand = saved.PlatformStand
end

-- Attach(scooter, player, "Driver"|"Passenger") -> handle | nil, reason
function RiderAttach.Attach(scooter, player, role)
	local char = player and player.Character
	if not char then return nil, "player has no character" end
	return RiderAttach.AttachCharacter(scooter, char, role, player)
end

-- Same as Attach, for a character model. `player` may be nil for a non-player rig.
function RiderAttach.AttachCharacter(scooter, char, role, player)
	local attName = ROLE_ATTACHMENT[role]
	if not attName then return nil, "unknown role " .. tostring(role) end

	local chassis = scooter and scooter.PrimaryPart
	if not chassis then return nil, "scooter has no PrimaryPart" end
	local foot = chassis:FindFirstChild(attName)
	if not foot then return nil, "chassis is missing " .. attName end

	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then return nil, "no character" end
	if hum.Health <= 0 then return nil, "character is dead" end

	hrp.Anchored = false
	if hum.SeatPart then hum.Sit = false end

	-- The stand attachment marks where the SOLES go, on the real deck surface. Lift
	-- the root by this avatar's own sole depth, measured from its joints so R6, R15
	-- and scaled avatars all line up, then drop it by the knee bend.
	local body = RiderPose.MeasureBody(char)
	local bend = (body.Rig == "R15") and RiderPose.HipDropForKnee(body, KNEE_ANGLE) or 0
	local lift = body.SoleDepth - bend

	local hold = Instance.new("Attachment")
	hold.Name = role .. "Hold"
	hold.CFrame = foot.CFrame * CFrame.new(0, lift, 0)
	hold.Parent = chassis

	-- Stop the Humanoid walking, and take away the body's mass and collisions,
	-- BEFORE it joins the scooter, so nothing about it can nudge the vehicle.
	local saved = lockMovement(hum)

	-- A rider adds no mass: the motor, brake and steering were tuned on the scooter
	-- alone, and having riders on board must not change how it drives. Restored on
	-- release.
	local savedMassless = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			savedMassless[d] = d.Massless
			d.Massless = true
		end
	end
	-- No part of a rider (arms, legs, accessories, tools) collides with anything
	-- while riding. See CollisionGroups.
	CollisionGroups.SetCharacterGroup(char, CollisionGroups.Rider)
	-- a huge hat, wings or back item is hidden for the ride only (see OversizedAccessories)
	local hiddenAccessories = OversizedAccessories.Hide(char)
	-- only a rider who actually had something hidden is told (the red notice at the bottom)
	if player and OversizedAccessories.HidAny(hiddenAccessories) then
		local notice = game:GetService("ReplicatedStorage"):FindFirstChild("ScooterSystem")
		notice = notice and notice:FindFirstChild("Remotes") and notice.Remotes:FindFirstChild("Notice")
		if notice then notice:FireClient(player, OversizedAccessories.NOTICE) end
	end

	-- Weld the rider to the chassis. Scooter and riders become ONE rigid assembly,
	-- simulated by one machine and replicated as one, so a rider can never trail,
	-- float or bounce relative to the deck on anybody's screen. A rider held by
	-- AlignPosition/AlignOrientation is a separate assembly that replicates on its
	-- own - measured: other screens saw both riders up to 0.5 studs behind the deck
	-- whenever the scooter pulled away. The weld places the root exactly on the hold
	-- point once; nothing writes a CFrame after that.
	local weld = Instance.new("Weld")
	weld.Name = "ScooterRiderWeld"
	weld.Part0, weld.Part1 = chassis, hrp
	weld.C0 = hold.CFrame
	-- which job this rider has, for their own machine: only the Driver's machine simulates
	-- the scooter, so only it balances, steers and slides it (ScooterBalance, RideGui, IceSlide)
	weld:SetAttribute("Role", role)
	weld.Parent = hrp

	-- The driver simulates the scooter, and with it everyone welded to it.
	if role == "Driver" then
		pcall(function() chassis:SetNetworkOwner(player) end)
	end

	local handle = {
		Player = player, Role = role, Scooter = scooter,
		Humanoid = hum, Character = char, Root = hrp,
		Hold = hold, Body = body,
		Saved = saved,
		SavedMassless = savedMassless,
		HiddenAccessories = hiddenAccessories,
		Instances = { hold, weld },
		Conns = {},
		Released = false,
	}

	-- let go by itself if the character dies or leaves, so nothing dangles - unless the
	-- rider is meant to stay on board through death (KeepOnDeath: a landmine throws the
	-- scooter with its riders; the ride ending lets go of them then)
	table.insert(handle.Conns, hum.Died:Connect(function()
		if not handle.KeepOnDeath then RiderAttach.Release(handle) end
	end))
	table.insert(handle.Conns, char.AncestryChanged:Connect(function(_, parent)
		if not parent then RiderAttach.Release(handle) end
	end))

	return handle
end

-- One machine should simulate the whole mechanism: the scooter AND everyone on it.
-- The weld already makes the rear rider part of the driver-owned assembly; this
-- just states that ownership explicitly.
function RiderAttach.SetSimulationOwner(handle, owner)
	if not handle or handle.Released or not owner then return end
	pcall(function() handle.Root:SetNetworkOwner(owner) end)
end

function RiderAttach.Release(handle)
	if not handle or handle.Released then return end
	handle.Released = true
	RiderPose.Remove(handle)
	for _, c in ipairs(handle.Conns) do pcall(function() c:Disconnect() end) end
	for _, o in ipairs(handle.Instances) do pcall(function() o:Destroy() end) end
	for part, was in pairs(handle.SavedMassless or {}) do
		if part.Parent then part.Massless = was end
	end
	if handle.Character and handle.Character.Parent then
		CollisionGroups.SetCharacterGroup(handle.Character, CollisionGroups.Character)
	end
	OversizedAccessories.Restore(handle.HiddenAccessories)   -- their oversized accessories are back
	local hum = handle.Humanoid
	restoreMovement(hum, handle.Saved)
	-- hand the character back to its own player
	local root = handle.Root
	if root and root.Parent then
		pcall(function()
			if handle.Player and handle.Player.Parent then
				root:SetNetworkOwner(handle.Player)
			else
				root:SetNetworkOwnershipAuto()
			end
		end)
	end
end

return RiderAttach
