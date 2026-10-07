-- Makes a real Roblox character LOOK like it is riding the scooter: soles planted
-- on the deck with a slight knee bend, a small forward lean, the driver's hands on
-- the grips, and the rear rider's hands holding the driver or working the motor.
--
-- Everything is IKControl, solved by the Animator on every client on top of the
-- normal animations. Nothing is anchored, no Humanoid is frozen, nothing writes a
-- CFrame per frame, and IK only ROTATES joints, so no limb can stretch. Hand targets
-- that would be out of reach are pulled in to what this avatar's arm can actually
-- reach, so arms never lock out straight either.
--
-- The rig points are attachments on the scooter's PHYSICAL skeleton (Chassis and
-- SteerColumn), never on the cosmetic meshes, so a future skin reuses them as-is:
--   Chassis      <Role>FootL/R  <Role>ElbowPoleL/R  <Role>LeanTarget
--                PassengerHoldL/R   (only used when there is no driver to hold)
--   SteerColumn  DriverGripL/R      (turn with the fork, so the hands follow steering)
-- Knee poles and the rear rider's throttle/brake reach are derived per avatar.

local RiderPose = {}

local REACH_USE = 0.92      -- never ask an arm for more than this share of its length

-- Rear rider's W / Space / S hand movements, relative to where that hand rests on
-- the driver (chassis axes: +X right, +Y up, -Z forward). Small on purpose.
local THROTTLE_REACH = Vector3.new( 0.08,  0.30, -0.80)   -- W: right hand forward and a little up
local BRAKE_REACH    = Vector3.new(-0.08, -0.12, -0.70)   -- Space: left hand forward and a little down
local REVERSE_REACH  = Vector3.new( 0.10, -0.22, -0.55)   -- S: right hand forward and down

local CHAINS = {
	R15 = {
		LeftArm  = { "LeftUpperArm",  "LeftHand"  },
		RightArm = { "RightUpperArm", "RightHand" },
		LeftLeg  = { "LeftUpperLeg",  "LeftFoot"  },
		RightLeg = { "RightUpperLeg", "RightFoot" },
		Torso    = { "UpperTorso",    "UpperTorso" },
		Shoulder = { L = "LeftShoulder",  R = "RightShoulder" },
		Feet     = { "LeftFoot", "RightFoot" },
		Hands    = { "LeftHand", "RightHand" },
	},
	R6 = {
		LeftArm  = { "Left Arm",  "Left Arm"  },
		RightArm = { "Right Arm", "Right Arm" },
		LeftLeg  = { "Left Leg",  "Left Leg"  },
		RightLeg = { "Right Leg", "Right Leg" },
		Shoulder = { L = "Left Shoulder", R = "Right Shoulder" },
		Feet     = { "Left Leg", "Right Leg" },
		Hands    = { "Left Arm", "Right Arm" },
	},
}

---------------------------------------------------------------- body measurement
-- Rest pose of every part relative to the HumanoidRootPart, from joint geometry
-- alone, so it does not depend on whatever animation is playing. Handles classic
-- Motor6D rigs and the newer AnimationConstraint rigs.
function RiderPose.MeasureBody(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local rig = (hum and hum.RigType == Enum.HumanoidRigType.R6) and "R6" or "R15"

	local links = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(links, { name = d.Name, p0 = d.Part0, p1 = d.Part1, c0 = d.C0, c1 = d.C1 })
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			table.insert(links, { name = d.Name, p0 = d.Attachment0.Parent, p1 = d.Attachment1.Parent,
				c0 = d.Attachment0.CFrame, c1 = d.Attachment1.CFrame })
		end
	end

	local rest = { [hrp] = CFrame.new() }
	local grew = true
	while grew do
		grew = false
		for _, l in ipairs(links) do
			if rest[l.p0] and not rest[l.p1] then
				rest[l.p1] = rest[l.p0] * l.c0 * l.c1:Inverse()
				grew = true
			end
		end
	end
	local function jointPos(name)
		for _, l in ipairs(links) do
			if l.name == name and rest[l.p0] then return (rest[l.p0] * l.c0).Position end
		end
	end

	local chains = CHAINS[rig]

	-- how far the lowest sole sits below the root = how high the root must be held
	local sole = 0
	for _, name in ipairs(chains.Feet) do
		local p = char:FindFirstChild(name)
		if p and rest[p] then sole = math.max(sole, -(rest[p].Position.Y - p.Size.Y / 2)) end
	end

	-- Ankle geometry, for two-bone leg IK: where the ankle sits inside the lower leg,
	-- and where it sits relative to the centre of the sole when standing flat.
	local ankles = {}
	for _, side in ipairs({ "Left", "Right" }) do
		local foot = char:FindFirstChild(side .. "Foot")
		for _, l in ipairs(links) do
			if l.name == side .. "Ankle" and foot and rest[l.p0] and rest[foot] then
				local ankleRest  = (rest[l.p0] * l.c0).Position
				local soleCentre = rest[foot].Position - Vector3.new(0, foot.Size.Y / 2, 0)
				ankles[side] = { InFoot = l.c1.Position, FromSole = ankleRest - soleCentre }
			end
		end
	end

	-- Wrist geometry. Arm IK controls the WRIST, not the hand centre: IKControl does
	-- not own the end effector's own joint, and measured, pinning the hand centre
	-- left it swung off target by exactly the wrist-to-hand distance.
	local wrists, wristToHand = {}, {}
	for _, side in ipairs({ "Left", "Right" }) do
		local hand = char:FindFirstChild(side .. "Hand")
		for _, l in ipairs(links) do
			if l.name == side .. "Wrist" and hand and rest[hand] and rest[l.p0] then
				wrists[side] = l.c1.Position
				wristToHand[side] = (rest[hand].Position - (rest[l.p0] * l.c0).Position).Magnitude
			end
		end
	end

	local shL, shR = jointPos(chains.Shoulder.L), jointPos(chains.Shoulder.R)
	local reach, wristReach = 0, nil
	local hand = char:FindFirstChild(chains.Hands[2])
	if shR and hand and rest[hand] then
		local el, wr = jointPos("RightElbow"), jointPos("RightWrist")
		if rig == "R15" and el and wr then
			-- sum the segments, so a bent rest pose cannot under-report the reach
			wristReach = (el - shR).Magnitude + (wr - el).Magnitude
			reach = wristReach + (rest[hand].Position - wr).Magnitude
		else
			reach = (rest[hand].Position - shR).Magnitude + hand.Size.Y / 2
		end
	end

	local hips = { Left = jointPos(rig == "R15" and "LeftHip" or "Left Hip"),
	               Right = jointPos(rig == "R15" and "RightHip" or "Right Hip") }

	local thigh, shin
	if rig == "R15" then
		local h, k, a = jointPos("RightHip"), jointPos("RightKnee"), jointPos("RightAnkle")
		if h and k and a then thigh, shin = (k - h).Magnitude, (a - k).Magnitude end
	end

	return {
		Rig = rig, Chains = chains, Rest = rest,
		SoleDepth = sole,
		Ankles = ankles,
		Hips = hips,
		Thigh = thigh, Shin = shin,
		Shoulder = { L = shL, R = shR },
		Reach = reach,
		WristReach = wristReach or reach,
		Wrists = wrists,
		WristToHand = wristToHand,
	}
end

-- How far to drop the hips so the knees settle at `kneeDeg` (180 = straight).
-- Worked out from this avatar's own thigh and shin: a fixed drop folded short legs
-- into a crouch (measured: 104 degrees) and barely bent long ones.
function RiderPose.HipDropForKnee(body, kneeDeg)
	local a, b = body.Thigh, body.Shin
	if not (a and b) then return 0 end
	local d = math.sqrt(a * a + b * b - 2 * a * b * math.cos(math.rad(kneeDeg)))
	return math.max(0, (a + b) - d)
end

---------------------------------------------------------------- helpers
-- Roblox's Animator (since a Roblox update, Oct 2026) only picks up the IKControls that are there
-- when it STARTS: measured, ones added later never moved a limb (riders stood bolt upright, hands
-- 2.1 studs off the grips) and ones removed later kept holding the limb where they left it.
-- Taking the Animator out and straight back in, in the same frame, restarts it with exactly the
-- IKControls there now; nothing else about the character changes, and in the same frame nothing
-- can make a second Animator. The server's change reaches every machine, so everyone's view of
-- this rider is restarted too. Harmless if Roblox fixes the Animator.
local function restartAnimator(hum)
	local an = hum and hum.Parent and hum:FindFirstChildOfClass("Animator")
	if not an then return end
	pcall(function()
		an.Parent = nil
		an.Parent = hum
	end)
end
RiderPose.RestartAnimator = restartAnimator

local function makeIK(hum, char, name, chain, target, pole, priority, smooth, offset, kind)
	local root = chain and char:FindFirstChild(chain[1])
	local eff  = chain and char:FindFirstChild(chain[2])
	if not (root and eff and target) then return nil end
	local k = Instance.new("IKControl")
	k.Name        = name
	k.Type        = kind or Enum.IKControlType.Position
	k.ChainRoot   = root
	k.EndEffector = eff
	k.Target      = target
	if pole then k.Pole = pole end
	k.Priority    = priority
	k.SmoothTime  = smooth
	if offset then k.EndEffectorOffset = offset end
	k.Weight      = 1
	k.Parent      = hum
	return k
end

-- pull a chassis-space point inside the arm's comfortable reach from the shoulder
local function reachable(shoulder, point, reach)
	local d = point - shoulder
	local max = reach * REACH_USE
	if d.Magnitude <= max then return point end
	return shoulder + d.Unit * max
end

---------------------------------------------------------------- public
-- Pose a rider who is already held by RiderAttach. For the rear rider, pass the
-- driver's handle so their hands rest on the driver's actual body.
function RiderPose.Apply(handle, driverHandle)
	if not handle or handle.Released or handle.Pose then return end
	local char, hum, body = handle.Character, handle.Humanoid, handle.Body
	local chassis = handle.Scooter.PrimaryPart
	local column  = handle.Scooter:FindFirstChild("SteerColumn")
	local role, ch = handle.Role, body.Chains
	local pose = { IK = {}, Made = {}, Arms = {}, Action = "idle" }
	handle.Pose = pose

	local function point(name) return chassis:FindFirstChild(name) end
	local function keep(k) if k then table.insert(pose.IK, k) end; return k end
	-- `pos` is chassis space. On the steering column the point turns with the fork.
	local function made(name, pos, onColumn)
		local a = Instance.new("Attachment")
		a.Name = name
		if onColumn and column then
			a.Parent = column
			a.WorldPosition = chassis.CFrame * pos
		else
			a.Parent = chassis
			a.Position = pos
		end
		table.insert(pose.Made, a)
		return a
	end
	-- Where the WRIST must go so the HAND CENTRE lands on `handPoint`, kept inside
	-- this arm's comfortable reach.
	local function wristFor(handPoint, shoulder, side)
		-- capped: some avatar hand meshes have a bounding box far bigger than the hand
		-- (measured 0.46 on one side, 0.27 on the other) and would drag the wrist back
		local w2h = math.min((body.WristToHand and body.WristToHand[side]) or 0, 0.3)
		local d = handPoint - shoulder
		local wrist = (d.Magnitude > w2h) and (handPoint - d.Unit * w2h) or handPoint
		return reachable(shoulder, wrist, body.WristReach)
	end
	local function armOffset(side)
		if body.Rig == "R6" then return CFrame.new(0, -1, 0) end
		local w = body.Wrists and body.Wrists[side]
		return w and CFrame.new(w) or nil
	end
	-- Swivel the hand about the wrist so its centre points at `target`. The arm IK
	-- only places the wrist; without this the hand just continues the forearm, and
	-- measured, a folded arm swung the hand 0.70 off the grip mid-turn. Single-joint
	-- LookAt, like the feet: the offset's origin is the wrist and it looks at the
	-- hand centre, so aiming it at the target lands the hand centre on the target.
	local function handAim(side, target, smooth)
		local w = body.Wrists and body.Wrists[side]
		if body.Rig ~= "R15" or not (w and target) then return nil end
		return keep(makeIK(hum, char, "ScooterHand" .. side:sub(1, 1), { side .. "Hand", side .. "Hand" },
			target, nil, 4, smooth, CFrame.lookAt(w, Vector3.zero, Vector3.zAxis), Enum.IKControlType.LookAt))
	end
	pose.Hands = {}

	local holdCF = handle.Hold.CFrame
	local shL = holdCF * (body.Shoulder.L or Vector3.new(-1, 0.5, 0))
	local shR = holdCF * (body.Shoulder.R or Vector3.new( 1, 0.5, 0))
	local function sole(name)
		local f = char:FindFirstChild(name)
		return f and CFrame.new(0, -f.Size.Y / 2, 0) or nil
	end

	-- Legs: soles flat on the deck, hips held a little low so the knees bend forward.
	--
	-- Two steps, because asking one IK for "sole exactly here AND foot exactly level"
	-- is over-constrained on real avatars: measured, Position IK tilted the foot 33
	-- degrees and folded the knee to 107, and Transform IK sank the soles 0.1-0.2 into
	-- the deck. Instead, two-bone IK puts the ANKLE exactly where a flat foot needs
	-- it (from this avatar's own rest geometry), then the foot is levelled by aiming
	-- its toe at a point far ahead at its own height. Each half is exactly solvable.
	-- (The toe uses LookAt because a single-part Rotation IK is degenerate: measured,
	-- it produced NaN foot CFrames.)
	local function leg(side, targetName)
		local target = point(targetName)
		local ankle = body.Ankles and body.Ankles[side]
		-- Each knee gets its OWN pole, straight ahead of its own hip. A single shared
		-- pole on the centreline pulled both knees toward the same spot: measured, one
		-- leg crossed over to the other side and the ankle missed by 0.93 studs.
		local hip = body.Hips and body.Hips[side]
		local poleX = hip and (holdCF * hip).X or (target and target.Position.X) or 0
		local pole = target and made("__" .. role .. "Knee" .. side,
			Vector3.new(poleX, target.Position.Y + 1.2, holdCF.Position.Z - 3))
		if body.Rig == "R15" and ankle and target then
			local ankleTarget = made("__" .. role .. "Ankle" .. side, target.Position + ankle.FromSole)
			-- The chain must END AT THE FOOT. Ending it at the lower leg left the knee
			-- fixed (measured: knees never moved from the idle pose, only the hip swung),
			-- so the controlled point is the ankle expressed in the foot's own space.
			keep(makeIK(hum, char, "ScooterLeg" .. side, { side .. "UpperLeg", side .. "Foot" },
				ankleTarget, pole, 1, 0, CFrame.new(ankle.InFoot)))
			local footPart = char:FindFirstChild(side .. "Foot")
			local half = footPart and footPart.Size.Y / 2 or 0.3
			local toe = made("__" .. role .. "Toe" .. side, target.Position + Vector3.new(0, half, -12))
			keep(makeIK(hum, char, "ScooterFoot" .. side, { side .. "Foot", side .. "Foot" },
				toe, nil, 2, 0, nil, Enum.IKControlType.LookAt))
		else
			local chain = (side == "Left") and ch.LeftLeg or ch.RightLeg
			local footName = (side == "Left") and ch.Feet[1] or ch.Feet[2]
			keep(makeIK(hum, char, "ScooterLeg" .. side, chain, target, pole, 1, 0, sole(footName)))
		end
	end
	leg("Left",  role .. "FootL")
	leg("Right", role .. "FootR")

	-- a slight forward lean
	local lean = keep(makeIK(hum, char, "ScooterLean", ch.Torso, point(role .. "LeanTarget"), nil, 2, 0, nil,
		Enum.IKControlType.LookAt))
	if lean then lean.Weight = 0.6 end

	if role == "Driver" then
		-- Wrist targets are placed on the STEERING COLUMN, so when the fork turns the
		-- hands go with it. Nothing extra has to happen on steer input.
		local function gripTarget(side, gripName, shoulder)
			local grip = column and column:FindFirstChild(gripName)
			if not grip then return nil end
			local gripC = chassis.CFrame:PointToObjectSpace(grip.WorldPosition)
			return made("__DriverWrist" .. side, wristFor(gripC, shoulder, side), true)
		end
		pose.Arms.L = keep(makeIK(hum, char, "ScooterArmL", ch.LeftArm,  gripTarget("Left",  "DriverGripL", shL),
			point("DriverElbowPoleL"), 3, 0.05, armOffset("Left")))
		pose.Arms.R = keep(makeIK(hum, char, "ScooterArmR", ch.RightArm, gripTarget("Right", "DriverGripR", shR),
			point("DriverElbowPoleR"), 3, 0.05, armOffset("Right")))
		-- and the hands point at the grips themselves, which turn with the fork
		pose.Hands.L = handAim("Left",  column and column:FindFirstChild("DriverGripL"), 0.05)
		pose.Hands.R = handAim("Right", column and column:FindFirstChild("DriverGripR"), 0.05)
	else
		-- Rear rider. Every hand target is worked out once, in chassis space, from this
		-- avatar's real shoulders and reach. The riders are rigidly held, so these
		-- points stay put relative to both bodies for the whole ride.
		local restL, restR
		if driverHandle and not driverHandle.Released and driverHandle.Body then
			local dc = driverHandle.Character
			local waist = dc:FindFirstChild("LowerTorso") or dc:FindFirstChild("Torso")
			local waistRest = waist and driverHandle.Body.Rest[waist]
			if waistRest then
				-- hands on the back of the driver's hips, one each side
				local base = driverHandle.Hold.CFrame * waistRest
				local sx, sz = waist.Size.X, waist.Size.Z
				restL = (base * CFrame.new(-(sx / 2 + 0.08), 0.1, sz * 0.3)).Position
				restR = (base * CFrame.new( (sx / 2 + 0.08), 0.1, sz * 0.3)).Position
			end
		end
		restL = restL or point("PassengerHoldL").Position
		restR = restR or point("PassengerHoldR").Position

		pose.Targets = {
			HoldL    = made("__RearHoldL",    wristFor(restL, shL, "Left")),
			HoldR    = made("__RearHoldR",    wristFor(restR, shR, "Right")),
			Throttle = made("__RearThrottle", wristFor(restR + THROTTLE_REACH, shR, "Right")),
			Brake    = made("__RearBrake",    wristFor(restL + BRAKE_REACH,    shL, "Left")),
			Reverse  = made("__RearReverse",  wristFor(restR + REVERSE_REACH,  shR, "Right")),
		}
		-- where the hand CENTRES go, for the hand-aim IK
		pose.HandPoints = {
			HoldL    = made("__RearHandHoldL",    restL),
			HoldR    = made("__RearHandHoldR",    restR),
			Throttle = made("__RearHandThrottle", restR + THROTTLE_REACH),
			Brake    = made("__RearHandBrake",    restL + BRAKE_REACH),
			Reverse  = made("__RearHandReverse",  restR + REVERSE_REACH),
		}
		-- SmoothTime makes every client glide the hand between targets instead of
		-- snapping, which is what makes W/S read as a hand movement.
		pose.Arms.L = keep(makeIK(hum, char, "ScooterArmL", ch.LeftArm,  pose.Targets.HoldL,
			point("PassengerElbowPoleL"), 3, 0.15, armOffset("Left")))
		pose.Arms.R = keep(makeIK(hum, char, "ScooterArmR", ch.RightArm, pose.Targets.HoldR,
			point("PassengerElbowPoleR"), 3, 0.15, armOffset("Right")))
		pose.Hands.L = handAim("Left",  pose.HandPoints.HoldL, 0.15)
		pose.Hands.R = handAim("Right", pose.HandPoints.HoldR, 0.15)
		char:SetAttribute("ScooterAction", "idle")
	end
	restartAnimator(hum)   -- so the Animator takes up the IKControls just made
end

-- Rear rider only. Follows the motor mode the server actually accepted:
--   forward -> right hand forward to the throttle   (W)
--   brake   -> left hand forward-down to the brake  (Space)
--   reverse -> right hand forward-down              (S)
--   anything else -> both hands back on the driver
local ACTION = { forward = "throttle", go = "throttle", brake = "brake", reverse = "reverse" }
function RiderPose.SetAction(handle, mode)
	if not handle or handle.Released or handle.Role ~= "Passenger" then return end
	local pose = handle.Pose
	if not (pose and pose.Targets) then return end
	local action = ACTION[mode] or "idle"
	if pose.Action == action then return end
	pose.Action = action

	local t, h = pose.Targets, pose.HandPoints
	local right = (action == "throttle" and "Throttle") or (action == "reverse" and "Reverse") or "HoldR"
	local left  = (action == "brake" and "Brake") or "HoldL"
	if pose.Arms.R  then pose.Arms.R.Target  = t[right] end
	if pose.Arms.L  then pose.Arms.L.Target  = t[left]  end
	if pose.Hands.R then pose.Hands.R.Target = h[right] end
	if pose.Hands.L then pose.Hands.L.Target = h[left]  end
	if handle.Character and handle.Character.Parent then
		handle.Character:SetAttribute("ScooterAction", action)
	end
end

function RiderPose.Remove(handle)
	local pose = handle and handle.Pose
	if not pose then return end
	handle.Pose = nil
	for _, k in ipairs(pose.IK) do pcall(function() k:Destroy() end) end
	for _, a in ipairs(pose.Made) do pcall(function() a:Destroy() end) end
	restartAnimator(handle.Humanoid)   -- and lets go of them, so the body is free again
	if handle.Character and handle.Character.Parent then
		handle.Character:SetAttribute("ScooterAction", nil)
	end
end

return RiderPose
