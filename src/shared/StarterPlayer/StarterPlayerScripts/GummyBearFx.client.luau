-- Gummy Bear Statue: floats gently up and down with a slight sway, and keeps raising its
-- lollipop higher and lowering it again. Drawn on each player's machine (smooth, and costs the
-- server nothing). The raised arm is the LollipopArm, LollipopPaw and everything in Lollipop,
-- turning about the Shoulder marker.
-- The head (Head, Snout, Nose, Mouth, Eye(Shine), Ear(Inner), Cheek) watches THIS player's
-- scooter while it is within LookRange: each client sees the bear looking at its own ride,
-- so both riders of scooter A see it follow A while the riders of scooter B see it follow B.
-- It notices a moment late, turns with a little weight (a damped spring, never snapping),
-- tilts slightly into fast turns, and turns only as far as a neck could - past that it
-- loses interest and drifts back to idly glancing around.
-- Tuning: attributes on the statue model (tag "GummyBear")
--   BobHeight / BobTime     how far and how slowly it floats up and down (studs, seconds)
--   SwayDeg                 how far it leans side to side
--   RaiseDeg / RaiseTime    how far the lollipop arm lifts, and how long one lift takes
--   LookRange               studs from the head at which it starts watching your scooter
--   LookYawDeg / LookPitchDeg   how far the head turns sideways / tips down at most

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local player = Players.LocalPlayer

local HEAD_PARTS = { Head = true, Snout = true, Nose = true, Mouth = true, Eye = true,
	EyeShine = true, Ear = true, EarInner = true, Cheek = true }

local NOTICE_DELAY = 0.3    -- seconds before it reacts to a scooter coming into range
local FORGET_DELAY = 1.0    -- seconds it keeps staring where you left before looking away
local GIVE_UP_DEG  = 125    -- a target further round than this is behind it: stop watching
local TRACK_STIFF  = 4.5    -- spring speed while watching (higher = quicker head)
local IDLE_STIFF   = 1.6    -- spring speed while idle / returning (lazier)
local MAX_TURN     = math.rad(140)  -- fastest the head may turn, per second
local ROLL_K       = 0.12   -- head tilt into a turn, per rad/s of turning
local AIM_UP       = 3      -- look at the riders, not the deck

local statues = {}

-- the chassis this player is welded to, if they are riding (as ScooterFx)
local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

-- critically damped spring toward target, with a speed cap
local function spring(x, v, target, w, dt)
	v += ((target - x) * w * w - 2 * w * v) * dt
	v = math.clamp(v, -MAX_TURN, MAX_TURN)
	return x + v * dt, v
end

local function add(m)
	if statues[m] or not m:IsA("Model") then return end
	local sh = m:FindFirstChild("Shoulder")
	local tier = m:FindFirstChild("Pedestal") and m.Pedestal:FindFirstChild("Tier")
	if not (sh and tier) then return end
	local centre = CFrame.lookAt(tier.Position, tier.Position + sh.CFrame.LookVector)
	local arm = {}
	for _, n in ipairs({ "LollipopArm", "LollipopPaw" }) do
		local p = m:FindFirstChild(n, true) if p then arm[p] = true end
	end
	local lolly = m:FindFirstChild("Lollipop")
	if lolly then for _, p in ipairs(lolly:GetDescendants()) do if p:IsA("BasePart") then arm[p] = true end end end
	local bear = m:FindFirstChild("Bear")
	local head = bear and bear:FindFirstChild("Head")
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= sh then
			local isHead = head ~= nil and p.Parent == bear and HEAD_PARTS[p.Name] == true
			table.insert(parts, { p, p.CFrame, arm[p] == true, isHead })
		end
	end
	-- the neck: a little below the middle of the head ball, facing where the bear faces
	local neck
	if head then
		local np = head.Position - Vector3.yAxis * head.Size.Y * 0.35
		local fwd = head.CFrame.LookVector * Vector3.new(1, 0, 1)
		neck = CFrame.lookAt(np, np + fwd.Unit)
	end
	statues[m] = { centre = centre, shoulder = sh.CFrame, parts = parts, scale = m:GetScale(), neck = neck,
		yaw = 0, pitch = 0, yawV = 0, pitchV = 0, roll = 0, seenFor = 0, lostFor = math.huge,
		lastYaw = 0, lastPitch = 0, idleSeed = math.random() * 100 }
end

for _, m in ipairs(CollectionService:GetTagged("GummyBear")) do add(m) end
CollectionService:GetInstanceAddedSignal("GummyBear"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("GummyBear"):Connect(function(m) statues[m] = nil end)

-- where the head wants to point this frame (yaw, pitch, stiffness), relative to rest
local function lookGoal(m, s, neckNow, dt, t)
	local range = (m:GetAttribute("LookRange") or 110) * s.scale
	local maxYaw = math.rad(m:GetAttribute("LookYawDeg") or 70)
	local maxPitch = math.rad(m:GetAttribute("LookPitchDeg") or 50)
	local chassis = myChassis()
	local inView = false
	local yaw, pitch
	if chassis and chassis.Parent then
		local lp = neckNow:PointToObjectSpace(chassis.Position + Vector3.yAxis * AIM_UP)
		local dist = lp.Magnitude
		-- a bit of slack on the way out so it doesn't flicker at the edge
		local r = s.seenFor > 0 and range * 1.15 or range
		if dist < r then
			yaw = math.atan2(-lp.X, -lp.Z)
			pitch = math.atan2(lp.Y, math.sqrt(lp.X * lp.X + lp.Z * lp.Z))
			inView = math.abs(yaw) < math.rad(GIVE_UP_DEG)
		end
	end
	if inView then
		s.seenFor += dt
		if s.seenFor >= NOTICE_DELAY then
			s.lostFor = 0
			-- clamp softly so it strains toward the limit rather than hitting a wall
			yaw = maxYaw * math.tanh(yaw / maxYaw)
			pitch = math.clamp(pitch, -maxPitch, maxPitch * 0.5)
			s.lastYaw, s.lastPitch = yaw, pitch
			return yaw, pitch, TRACK_STIFF
		end
	else
		s.seenFor = 0
		s.lostFor += dt
		if s.lostFor < FORGET_DELAY then
			return s.lastYaw, s.lastPitch, TRACK_STIFF
		end
	end
	-- idle: slow, uneven glances about, a little downward at the road
	local k = t + s.idleSeed
	local iy = math.rad(12) * (math.sin(k * 0.23) + 0.5 * math.sin(k * 0.61))
	local ip = math.rad(-8) + math.rad(4) * math.sin(k * 0.37)
	return iy, ip, IDLE_STIFF
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 20)
	local t = os.clock()
	for m, s in pairs(statues) do
		if not m.Parent then statues[m] = nil continue end
		local bobH  = (m:GetAttribute("BobHeight") or 0.8) * s.scale
		local bobT  = m:GetAttribute("BobTime") or 4
		local sway  = math.rad(m:GetAttribute("SwayDeg") or 1.5)
		local raise = math.rad(m:GetAttribute("RaiseDeg") or 30)
		local rT    = m:GetAttribute("RaiseTime") or 3.2
		-- the whole statue: up and down, leaning a touch side to side on a slower beat
		local bob  = math.sin(t / bobT * math.pi * 2) * bobH
		local lean = math.sin(t / (bobT * 1.3) * math.pi * 2) * sway
		local c = s.centre
		local body = c * CFrame.new(0, bob, 0) * CFrame.fromAxisAngle(Vector3.zAxis, lean) * c:Inverse()
		-- the lollipop arm: eases up to RaiseDeg and back down (sideways, about the shoulder)
		local lift = (1 - math.cos(t / rT * math.pi * 2)) / 2 * raise
		local sh = s.shoulder
		local armMove = sh * CFrame.fromAxisAngle(Vector3.zAxis, lift) * sh:Inverse()
		-- the head: turns about the neck toward this player's scooter
		local headMove = CFrame.identity
		if s.neck then
			local gy, gp, w = lookGoal(m, s, body * s.neck, dt, t)
			s.yaw, s.yawV = spring(s.yaw, s.yawV, gy, w, dt)
			s.pitch, s.pitchV = spring(s.pitch, s.pitchV, gp, w, dt)
			-- tilt a touch into the turn, easing back as it settles
			local rollGoal = math.clamp(s.yawV * ROLL_K, -math.rad(8), math.rad(8))
			s.roll += (rollGoal - s.roll) * (1 - math.exp(-6 * dt))
			local n = s.neck
			headMove = n * CFrame.Angles(0, s.yaw, 0) * CFrame.Angles(s.pitch, 0, s.roll) * n:Inverse()
		end
		for _, e in ipairs(s.parts) do
			if e[4] then
				e[1].CFrame = body * headMove * e[2]
			else
				e[1].CFrame = e[3] and (body * armMove * e[2]) or (body * e[2])
			end
		end
	end
end)
