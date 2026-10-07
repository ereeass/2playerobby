-- Scooter riding polish, on this client only (nothing here changes how a ride drives):
--   Motor  every scooter hums with a soft electric whine: almost silent at rest,
--          rising in pitch with speed and a little louder while accelerating, and
--          easing off as it slows. The sound is the MotorHum Sound on the scooter
--          template's Chassis (each model in ServerStorage.ScooterModels): change its SoundId,
--          Volume (the loudest it gets) or regions there.
--   FOV    while this player rides, the camera's field of view widens with the
--          scooter's real speed (a touch more while speeding up) and narrows as it
--          slows and when the ride ends. It follows speed, not keys, and glides
--          through two smoothing stages, so quick W/S taps never make it flick.
--          While a cutscene has the camera (ScooterSystem.Cinematic) it waits.
--   Trail  a scooter's speed effects are the ParticleEmitters inside any Chassis
--          attachment whose name ends in "Trail" (the Ice Scooter's IceTrail; the Bee
--          Scooter's Left/RightMotorTrail and HoneyTrail): nothing standing still,
--          more with speed, a little more while speeding up. An emitter's rates are
--          its RateBase / RateSpeed / RatePush attributes (the Ice emitters use the
--          TRAIL table). The emitters belong to the scooter, so they go when it does.
--   Decals the ParticleEmitters inside any Chassis attachment whose name ends in
--          "Decals" (the Bee Scooter's HoneyDecals: a bee, a honey jar, a honeycomb)
--          send out ONE picture every Interval seconds (the attachment's attribute,
--          1 by default) while moving, none standing still. The pictures take turns
--          in a shuffled order: each once before any repeats, never twice running.
--   Bee    Motor6Ds with a Flutter attribute (the Bee Scooter's wings) buzz: barely
--          at rest, fast and wide at speed. Motor6Ds with a Sway attribute (its
--          antennae) bob gently and lean back while speeding up. Visual only: they
--          move massless, non-colliding parts, on this client.
--   Brake  while the server marks a scooter Braking (RideManager: its rear rider
--          HOLDS THE BRAKE - Space, or the touch Brake pedal - never W or S), the
--          tyres that touch the ground give a very soft screech and a few sparks. It
--          eases in, loops while the brake is held and fades quickly when it is let go,
--          so it never clicks; nothing in the air, nothing standing still. The sound
--          and sparks are this script's BrakeScreech and BrakeSparks.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local Cinematic = require(game:GetService("ReplicatedStorage"):WaitForChild("ScooterSystem"):WaitForChild("Cinematic"))

local player = Players.LocalPlayer

local TOP_SPEED   = 20.8   -- studs/s at Config.MaxAngularVelocity
local ACCEL_FULL  = 12     -- studs/s^2 that counts as accelerating hard

-- motor, as fractions of MotorHum.Volume
local VOL_IDLE    = 0.08   -- at rest
local VOL_SPEED   = 0.62   -- added at top speed
local VOL_PUSH    = 0.30   -- added while accelerating hard
local PITCH_IDLE  = 0.75
local PITCH_SPEED = 0.5    -- added at top speed
local PITCH_PUSH  = 0.06   -- added while accelerating hard

-- field of view, degrees added to the normal FOV
local FOV_SPEED   = 9      -- at top speed
local FOV_PUSH    = 2      -- while accelerating hard
local FOV_RISE    = 4      -- smoothing while widening (higher = quicker)
local FOV_FALL    = 2.8    -- smoothing while narrowing, a little gentler

-- ice trail, particles per second: base once moving + more at top speed + more
-- while accelerating hard. Below TRAIL_MIN_SPEED (a share of top speed) it stops.
local TRAIL = {
	IceFrost  = { base = 3, speed = 12, push = 6 },
	IceBits   = { base = 4, speed = 18, push = 10 },
	IceGlints = { base = 1, speed = 5,  push = 4 },
}
local TRAIL_MIN_SPEED = 0.06

-- bee wings (Flutter) and antennae (Sway)
local FLAP_IDLE_DEG, FLAP_SPEED_DEG = 2, 16     -- wing swing at rest / added at top speed
local FLAP_IDLE_HZ,  FLAP_SPEED_HZ  = 0.8, 13   -- wing beats per second at rest / added at top speed
local SWAY_DEG,  SWAY_HZ            = 3, 0.9    -- antennae: a gentle bob
local QUIVER_DEG, QUIVER_HZ         = 2.5, 7    -- ...a light quiver at top speed
local SWAY_PUSH_DEG                 = 10        -- ...and a lean back while speeding up
local MOTION_RANGE                  = 200       -- studs from the camera; farther scooters stay still

-- brake screech and sparks
local BRAKE_SOUND  = script:WaitForChild("BrakeScreech")   -- its Volume is the loudest it gets
local BRAKE_SPARKS = script:WaitForChild("BrakeSparks")
local BRAKE_FADE_IN, BRAKE_FADE_OUT = 9, 20              -- a smooth start, a quick stop
local BRAKE_VOL_SLOW = 0.55                              -- share of the full volume near a stop
local SPARKS_BASE, SPARKS_SPEED = 18, 40                 -- per tyre per second, + more at top speed
local brakeRay = RaycastParams.new()
brakeRay.FilterType = Enum.RaycastFilterType.Exclude
brakeRay.IgnoreWater = true
brakeRay.RespectCanCollide = true

local function approach(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local states = {}          -- [scooter model] = motion + sound state

local function track(scooter)
	if scooter:IsA("Model") and not states[scooter] then
		states[scooter] = { speed = 0, accel = 0, vol = 0, pitch = PITCH_IDLE }
	end
end
scooters.ChildAdded:Connect(track)
for _, s in ipairs(scooters:GetChildren()) do track(s) end

-- The hum plays from an attachment of this client's own that follows the chassis,
-- so when a ride ends and the scooter is removed it can still fade out instead
-- of cutting off.
local function startSound(st, chassis)
	local template = chassis:FindFirstChild("MotorHum")
	if not template then return end
	st.att = Instance.new("Attachment")
	st.att.Name = "ScooterMotor"
	st.att.Parent = workspace.Terrain
	st.maxVol = template.Volume
	st.sound = template:Clone()
	st.sound.Volume = 0
	st.sound.Parent = st.att
	st.sound:Play()
end

-- the chassis this player is welded to, if they are riding
local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local fovBase, fovMid, fovExtra = nil, 0, 0

-- a Rate is only written when it really changes, so a cruising scooter costs nothing
local function updateTrail(st, chassis)
	if not st.trail then
		st.trail = {}
		for _, att in ipairs(chassis:GetChildren()) do
			if att:IsA("Attachment") and att.Name:sub(-5) == "Trail" then
				for _, e in ipairs(att:GetChildren()) do
					if e:IsA("ParticleEmitter") then
						local cfg = TRAIL[e.Name] or { base = e:GetAttribute("RateBase") or 0,
							speed = e:GetAttribute("RateSpeed") or 0, push = e:GetAttribute("RatePush") or 0 }
						table.insert(st.trail, { e = e, cfg = cfg, rate = -1 })
					end
				end
			end
		end
	end
	local moving = st.s > TRAIL_MIN_SPEED
	for _, t in ipairs(st.trail) do
		local r = moving and (t.cfg.base + t.cfg.speed * st.s + t.cfg.push * st.push) or 0
		if (r == 0 and t.rate ~= 0) or math.abs(r - t.rate) > 0.5 then
			t.rate = r
			t.e.Rate = r
		end
	end
end

-- the next picture from a Decals attachment's shuffled round
local function nextDecal(d)
	if #d.bag == 0 then
		for i = 1, #d.emitters do d.bag[i] = i end
		for i = #d.bag, 2, -1 do
			local j = math.random(i)
			d.bag[i], d.bag[j] = d.bag[j], d.bag[i]
		end
		-- the round is taken from the end: never start it with the one just shown
		if #d.bag > 1 and d.bag[#d.bag] == d.last then d.bag[1], d.bag[#d.bag] = d.bag[#d.bag], d.bag[1] end
	end
	local i = table.remove(d.bag)
	d.last = i
	return d.emitters[i]
end

-- one picture per Interval while moving. Timed from the last one sent, not from
-- when the scooter set off, so stopping and starting can never send them faster.
local function updateDecals(st, chassis)
	if not st.decals then
		st.decals = {}
		for _, att in ipairs(chassis:GetChildren()) do
			if att:IsA("Attachment") and att.Name:sub(-6) == "Decals" then
				local list = {}
				for _, e in ipairs(att:GetChildren()) do
					if e:IsA("ParticleEmitter") then table.insert(list, e) end
				end
				if #list > 0 then
					table.insert(st.decals, { emitters = list, bag = {}, last = nil, at = -math.huge,
						interval = att:GetAttribute("Interval") or 1 })
				end
			end
		end
	end
	if st.s <= TRAIL_MIN_SPEED then return end
	local now = os.clock()
	for _, d in ipairs(st.decals) do
		if now - d.at >= d.interval then
			d.at = now
			nextDecal(d):Emit(1)
		end
	end
end

-- wings and antennae; each Motor6D's Transform is set every frame (visual only)
local function updateMotion(st, scooter, dt)
	if not st.motors then
		st.motors, st.flap, st.t = {}, 0, 0
		for _, d in ipairs(scooter:GetDescendants()) do
			if d:IsA("Motor6D") and (d:GetAttribute("Flutter") or d:GetAttribute("Sway")) then table.insert(st.motors, d) end
		end
	end
	if #st.motors == 0 then return end
	st.t += dt
	st.flap = (st.flap + (FLAP_IDLE_HZ + FLAP_SPEED_HZ * st.s) * dt * 2 * math.pi) % (2 * math.pi)
	local flap = math.rad(FLAP_IDLE_DEG + FLAP_SPEED_DEG * st.s) * math.sin(st.flap)
	for _, m in ipairs(st.motors) do
		local side = m:GetAttribute("Flutter")
		if side then
			m.Transform = CFrame.Angles(0, 0, flap * side)
		else
			local ph = m:GetAttribute("Sway") or 0
			local a = math.rad(SWAY_DEG) * math.sin(st.t * SWAY_HZ * 2 * math.pi + ph)
				+ math.rad(QUIVER_DEG * st.s) * math.sin(st.t * QUIVER_HZ * 2 * math.pi + ph * 2)
				+ math.rad(SWAY_PUSH_DEG) * st.push
			m.Transform = CFrame.Angles(a, 0, 0)
		end
	end
end

-- sparks come from where each tyre meets the ground, held by the chassis (the
-- wheels themselves spin); the screech plays from this client's own attachment.
-- The tyres are the parts the drive motors turn (not the Cosmetic look-alikes).
local function setupBrake(st, scooter, chassis)
	st.brake = { vol = 0, wheels = {} }
	local up = chassis.CFrame.UpVector
	for _, hinge in ipairs(scooter:GetDescendants()) do
		local wheel = hinge:IsA("HingeConstraint") and hinge.ActuatorType == Enum.ActuatorType.Motor
			and hinge.Attachment1 and hinge.Attachment1.Parent
		if wheel and wheel:IsA("BasePart") then
			local r = math.max(wheel.Size.Y, wheel.Size.Z) / 2
			local att = Instance.new("Attachment")
			att.Name = "BrakeSparks"
			att.CFrame = chassis.CFrame:ToObjectSpace(CFrame.new(wheel.Position - up * r) * chassis.CFrame.Rotation)
			att.Parent = chassis
			local e = BRAKE_SPARKS:Clone()
			e.Parent = att
			table.insert(st.brake.wheels, { wheel = wheel, r = r, e = e, rate = 0 })
		end
	end
	local snd = BRAKE_SOUND:Clone()
	snd.Volume = 0
	snd.Parent = st.att or chassis
	st.brake.sound = snd
end

local function updateBrake(st, scooter, chassis, dt)
	local b = st.brake
	local on, back = false, true
	if chassis and scooter:GetAttribute("Braking") == true then
		-- only the tyres on the ground: no screech or sparks in the air
		local up = chassis.CFrame.UpVector
		brakeRay.FilterDescendantsInstances = { scooter }
		for _, w in ipairs(b.wheels) do
			w.down = workspace:Raycast(w.wheel.Position, -up * (w.r + 0.5), brakeRay) ~= nil
			on = on or w.down
		end
		back = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector) >= 0
	end
	if chassis then
		local dir = back and Enum.NormalId.Back or Enum.NormalId.Front   -- sparks fly the way the ground goes
		for _, w in ipairs(b.wheels) do
			local r = (on and w.down) and (SPARKS_BASE + SPARKS_SPEED * st.s) or 0
			if (r == 0 and w.rate ~= 0) or math.abs(r - w.rate) > 0.5 then w.rate = r; w.e.Rate = r end
			if w.e.EmissionDirection ~= dir then w.e.EmissionDirection = dir end
		end
	end
	-- the screech: fades in as braking starts, loops while held, fades out after
	local target = on and (BRAKE_VOL_SLOW + (1 - BRAKE_VOL_SLOW) * st.s) or 0
	b.vol = approach(b.vol, target, on and BRAKE_FADE_IN or BRAKE_FADE_OUT, dt)
	local snd = b.sound
	if target > 0 and not snd.IsPlaying then
		-- from a random point in the loop, so repeated stops never sound identical
		snd.TimePosition = math.random() * math.max(snd.TimeLength - 0.2, 0)
		snd:Play()
	elseif target == 0 and b.vol < 0.005 and snd.IsPlaying then
		snd:Stop()
	end
	snd.Volume = BRAKE_SOUND.Volume * b.vol
	snd.PlaybackSpeed = BRAKE_SOUND.PlaybackSpeed * (0.92 + 0.12 * st.s)
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.clamp(dt, 1 / 240, 1 / 20)

	---------------------------------------------- motor
	for scooter, st in pairs(states) do
		local alive   = scooter.Parent ~= nil
		local chassis = alive and scooter.PrimaryPart or nil
		if chassis then
			if not st.sound then startSound(st, chassis) end
			local v = chassis.AssemblyLinearVelocity
			local prev = st.speed
			st.speed = approach(st.speed, Vector3.new(v.X, 0, v.Z).Magnitude, 10, dt)
			st.accel = approach(st.accel, (st.speed - prev) / dt, 6, dt)
			if st.att then st.att.WorldPosition = chassis.Position end
		end
		st.s    = math.clamp(st.speed / TOP_SPEED, 0, 1)
		st.push = math.clamp(st.accel / ACCEL_FULL, 0, 1)
		if chassis then
			updateTrail(st, chassis)
			updateDecals(st, chassis)
			local cam = workspace.CurrentCamera
			if cam and (cam.CFrame.Position - chassis.Position).Magnitude < MOTION_RANGE then updateMotion(st, scooter, dt) end
			if not st.brake then setupBrake(st, scooter, chassis) end
		end
		if st.brake then updateBrake(st, scooter, chassis, dt) end

		-- gone or streamed out: fade to silence
		local volTarget = chassis and (VOL_IDLE + VOL_SPEED * st.s + VOL_PUSH * st.push) or 0
		st.vol   = approach(st.vol, volTarget, chassis and 5 or 8, dt)
		st.pitch = approach(st.pitch, PITCH_IDLE + PITCH_SPEED * st.s + PITCH_PUSH * st.push, 4, dt)
		if st.sound then
			st.sound.Volume = st.maxVol * st.vol
			st.sound.PlaybackSpeed = st.pitch
		end
		if not alive and st.vol < 0.01 then
			if st.att then st.att:Destroy() end
			states[scooter] = nil
		end
	end

	---------------------------------------------- field of view
	-- a cutscene (Cinematic) has the camera: the lens is its own, and the ride's zoom
	-- carries on from where it was once it's over
	if Cinematic.IsActive() then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local chassis = myChassis()
	local st = chassis and states[chassis.Parent]
	if st and not fovBase then fovBase = cam.FieldOfView end   -- the normal FOV, as the ride starts
	if fovBase then
		local target = st and (FOV_SPEED * st.s + FOV_PUSH * st.push) or 0
		-- two stages in a row, so every change starts and settles gently
		fovMid   = approach(fovMid, target, target > fovMid and FOV_RISE or FOV_FALL, dt)
		fovExtra = approach(fovExtra, fovMid, fovMid > fovExtra and FOV_RISE or FOV_FALL, dt)
		if not st and fovMid < 0.05 and fovExtra < 0.05 then
			cam.FieldOfView = fovBase              -- ride over: exactly back to normal, then let go
			fovBase, fovMid, fovExtra = nil, 0, 0
		else
			cam.FieldOfView = fovBase + fovExtra
		end
	end
end)
