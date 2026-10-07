-- Footsteps: a grass, dirt or rock step sound each time a foot lands.
--
-- Private to each player: every client plays ONLY its own player's footsteps.
-- Detection, surface, timing and the Sound instances all live on this client (never
-- on the server, so nothing replicates), and other players' characters are never
-- given footsteps here - each player hears their own on their own client. No
-- server script and no remotes.
--
--   Settings  (module inside this script)  volume and sound ids - tweak loudness here
--   Surface   (module inside this script)  which surfaces count as grass / dirt / rock
--
-- Timing: one step per stride of distance walked, so faster walking = quicker steps
-- and standing still = none. Each time a foot is seen landing in the walk/run
-- animation (its height above the ground dips) the rhythm is pulled onto that
-- footfall and the stride length is learnt from it, so steps land with the feet at
-- any speed, avatar size or animation pack. (R6 / feet that don't lift: stride only.)
--
-- Silent while jumping, falling, sitting, swimming, climbing, dead, standing still
-- or riding a scooter (RiderAttach puts riders in PlatformStand).
--
-- Roblox's default looping "Running" footstep sound (RbxCharacterSounds) plays every
-- player's steps on every client, so it is muted on ALL characters: your own steps
-- come from here, and nobody else's are heard. Its jump, landing and other sounds
-- are untouched.

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local PhysicsService  = game:GetService("PhysicsService")

local Settings = require(script:WaitForChild("Settings"))
local Surface  = require(script:WaitForChild("Surface"))

-- Each sound file is a recording of several footsteps in a row. These are the single
-- steps inside them - { start, length, evening-out factor } in seconds - measured
-- from the waveforms, so one footfall plays exactly one step. Gain balances the
-- recordings against each other: at Settings.Volume = 1 each is about as loud as
-- Roblox's default footsteps. A sound id not listed here is played from its start.
local CLIPS = {
	[140375026362889] = { -- Grass footsteps (a soft rustle, recorded quietly)
		Gain = 2.07,
		Steps = {
			{ 0.12, 0.28, 1.34 }, { 0.40, 0.26, 1.18 }, { 0.66, 0.26, 1.13 }, { 0.92, 0.25, 1.00 },
			{ 1.17, 0.26, 0.98 }, { 1.43, 0.27, 0.96 }, { 1.70, 0.29, 0.89 },
		},
	},
	[120506599872820] = { -- Dirt footsteps
		Gain = 0.19,
		Steps = {
			{ 0.105, 0.295, 0.85 }, { 0.400, 0.265, 1.04 }, { 0.665, 0.285, 0.79 }, { 0.950, 0.260, 1.29 },
			{ 1.210, 0.300, 1.01 }, { 1.515, 0.300, 0.90 }, { 1.820, 0.280, 0.93 }, { 2.100, 0.300, 1.11 },
			{ 2.415, 0.300, 0.90 }, { 2.730, 0.300, 0.89 }, { 3.040, 0.300, 1.17 }, { 3.360, 0.300, 0.94 },
			{ 3.680, 0.300, 1.02 }, { 3.990, 0.290, 1.14 }, { 4.280, 0.290, 1.00 },
		},
	},
	[98950681642146] = { -- Rock footsteps
		Gain = 0.45,
		Steps = {
			{ 0.280, 0.300, 1.05 }, { 0.595, 0.270, 0.98 }, { 0.865, 0.300, 0.82 }, { 1.175, 0.250, 1.25 },
			{ 1.425, 0.275, 1.02 }, { 1.700, 0.240, 1.30 }, { 1.940, 0.285, 0.95 }, { 2.225, 0.265, 1.23 },
			{ 2.490, 0.265, 0.88 }, { 2.755, 0.300, 0.90 },
		},
	},
}

local WALK_STATES = {
	[Enum.HumanoidStateType.Running]          = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
}
local FEET = {
	[Enum.HumanoidRigType.R15] = { "LeftFoot", "RightFoot" },
	[Enum.HumanoidRigType.R6]  = { "Left Leg", "Right Leg" },
}

local MOVING_SPEED  = 1.5  -- studs/s over the ground; slower counts as standing still
local SETTLE_TIME   = 0.25 -- the foot that lands as you come to a stop still sounds
local STRIDE        = 4.3  -- studs per step at normal size (default run at speed 16)
local MIN_LIFT      = 0.15 -- feet must swing this much (x size) to follow the animation
local SWING_CYCLES  = 1.3  -- a foot's swing is judged over its last ~1.3 walk cycles
local STRIKE        = 0.3  -- a foot has landed when it drops into the bottom 30% of its swing
local REARM         = 0.6  -- and it must rise above 60% before it can land again
local AIR_GRACE     = 0.2  -- off the ground/not walking this long forgets the stride; shorter
                           -- blips (stepping up a ledge flips to Climbing for a frame) don't
local MIN_GAP       = 0.12 -- never two steps closer together than this
local FOOT_GAP      = 0.25 -- nor the same foot landing twice
local FADE          = 0.06 -- each step fades out over its last 60 ms
local ROLLOFF_MIN   = 5    -- full volume within this many studs of the camera
local ROLLOFF_MAX   = 150  -- silent beyond this (only when zoomed right out)

local rng = Random.new()

local function assetNumber(v)
	return tonumber(string.match(tostring(v), "%d+"))
end

-- which surfaces' sounds actually loaded; a broken id falls back to another surface
local usable = {}
for kind, id in pairs(Settings.Sounds) do
	task.spawn(function()
		local probe = Instance.new("Sound")
		probe.SoundId = "rbxassetid://" .. tostring(assetNumber(id))
		local ok = false
		pcall(function()
			ContentProvider:PreloadAsync({ probe }, function(_, status)
				ok = status == Enum.AssetFetchStatus.Success
			end)
		end)
		usable[kind] = ok
		probe:Destroy()
		if not ok then
			warn(string.format("[Footsteps] %s sound %s did not load; using another surface's sound", kind, tostring(id)))
		end
	end)
end

local localPlayer = Players.LocalPlayer

-- rays see what the character stands on: collidable parts, never the character
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local current = nil -- the tracker for this player's own character

local function newTracker(char)
	rayParams.FilterDescendantsInstances = { char }
	-- characters don't collide with scooters (CollisionGroups), so neither do the rays
	pcall(function()
		if PhysicsService:IsCollisionGroupRegistered("Characters") then
			rayParams.CollisionGroup = "Characters"
		end
	end)
	return {
		Character = char, Feet = {}, Sounds = {}, Tweens = {}, LastIndex = {},
		LastStep = 0, LastMoving = -math.huge, Travelled = 0,
	}
end

local function castDown(origin, length)
	return workspace:Raycast(origin, Vector3.new(0, -length, 0), rayParams)
end

-- height of a foot's lowest point above the ground hit straight below it
local function heightAbove(part, hit)
	local cf, s = part.CFrame, part.Size
	local depth = math.abs(cf.RightVector.Y) * s.X
		+ math.abs(cf.UpVector.Y) * s.Y
		+ math.abs(cf.LookVector.Y) * s.Z
	return cf.Position.Y - depth / 2 - hit.Position.Y
end

local function soundFor(tr, root, kind)
	local emitter = tr.Emitter
	if not (emitter and emitter.Parent == root) then
		if emitter then
			emitter:Destroy()
		end
		emitter = Instance.new("Attachment")
		emitter.Name = "Footsteps"
		emitter.Archivable = false
		emitter.Parent = root
		tr.Emitter = emitter
		table.clear(tr.Sounds)
		table.clear(tr.Tweens)
	end
	local sound = tr.Sounds[kind]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = kind
		sound.Archivable = false
		sound.SoundId = "rbxassetid://" .. tostring(assetNumber(Settings.Sounds[kind]))
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = ROLLOFF_MIN
		sound.RollOffMaxDistance = ROLLOFF_MAX
		sound.Volume = 0
		sound.Parent = emitter
		tr.Sounds[kind] = sound
	end
	return sound
end

local function play(tr, root, kind, at)
	if usable[kind] == false then
		kind = (usable.Rock and "Rock") or (usable.Dirt and "Dirt") or (usable.Grass and "Grass")
		if not kind then
			return
		end
	end
	local volume = Settings.Volume * (Settings.SurfaceVolume[kind] or 1)
	if volume <= 0 then
		return
	end
	local sound = soundFor(tr, root, kind)
	tr.Emitter.WorldPosition = at -- the sound comes from where the foot landed

	local speed = 1 + rng:NextNumber(-Settings.PitchVariation, Settings.PitchVariation)
	volume *= 1 + rng:NextNumber(-Settings.VolumeVariation, Settings.VolumeVariation)

	local old = tr.Tweens[kind]
	if old then
		old:Cancel()
		tr.Tweens[kind] = nil
	end

	local clip = CLIPS[assetNumber(Settings.Sounds[kind])]
	local step
	if clip then
		-- a random step from the recording, never the same one twice running
		local steps = clip.Steps
		local i = rng:NextInteger(1, #steps)
		if #steps > 1 and i == tr.LastIndex[kind] then
			i = i % #steps + 1
		end
		tr.LastIndex[kind] = i
		step = steps[i]
		volume *= clip.Gain * step[3]
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(step[1], step[1] + step[2])
		sound.TimePosition = step[1]
	else
		sound.PlaybackRegionsEnabled = false
		sound.TimePosition = 0
	end
	sound.PlaybackSpeed = speed
	sound.Volume = math.min(volume, 10)
	sound:Play()

	if step then
		local tween = TweenService:Create(sound, TweenInfo.new(FADE, Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out, 0, false, math.max(0, step[2] / speed - FADE)), { Volume = 0 })
		tr.Tweens[kind] = tween
		tween:Play()
	end
end

-- An invisible collider (like the spawn pad lying on the path) sounds like the
-- visible ground just under it, unless it has its own FootstepSurface attribute.
local function visibleSurface(hit)
	for _ = 1, 3 do
		local part = hit.Instance
		if part:IsA("Terrain") or part.Transparency < 0.95 or part:GetAttribute("FootstepSurface") then
			return hit
		end
		local below = castDown(hit.Position - Vector3.new(0, 0.01, 0), 3)
		if not below then
			return hit
		end
		hit = below
	end
	return hit
end

-- one step, sounding the surface that was hit under the landing foot (or the body)
local function step(tr, root, hit, now)
	if now - tr.LastStep < MIN_GAP then
		return
	end
	tr.LastStep = now
	tr.Travelled = 0
	tr.FirstStep = false
	play(tr, root, Surface.Of(visibleSurface(hit)), hit.Position)
end

local function forgetSwing(foot)
	table.clear(foot.Times)
	table.clear(foot.Heights)
	foot.Armed = false
end

-- forget any half-finished stride (airborne, seated, riding...)
local function rest(tr)
	for _, foot in ipairs(tr.Feet) do
		forgetSwing(foot)
	end
	tr.Travelled = 0
	tr.WasMoving = false
end

-- Roblox's default looping footstep sound: muted on every character (see top)
local function muteDefault(root)
	local default = root:FindFirstChild("Running")
	if default and (default:IsA("Sound") or default:IsA("AudioPlayer")) and default.Volume ~= 0 then
		default.Volume = 0
	end
end

-- not walking on the ground this frame: no step; forget the stride once it lasts
local function offGround(tr, now)
	tr.OffSince = tr.OffSince or now
	if now - tr.OffSince > AIR_GRACE then
		rest(tr)
	end
end

local function update(tr, dt, now)
	local char = tr.Character
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then
		rest(tr)
		return
	end

	if hum.Health <= 0 or hum.PlatformStand or hum.Sit
		or not WALK_STATES[hum:GetState()] then
		offGround(tr, now)
		return
	end

	-- on the ground? (the root floats HipHeight above it; R6 legs are 2 studs)
	local legs = hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight
	local rootHeight = root.Size.Y / 2 + legs
	local reach = rootHeight + 1.5
	local ground = castDown(root.Position, reach)
	if not ground then
		offGround(tr, now)
		return
	end
	tr.OffSince = nil
	local size = math.clamp(rootHeight / 3, 0.5, 4)

	-- speed over the ground (standing on something moving doesn't count as walking)
	local vel = root.AssemblyLinearVelocity - ground.Instance:GetVelocityAtPosition(ground.Position)
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if speed > MOVING_SPEED then
		tr.LastMoving = now
	end
	local moving = now - tr.LastMoving <= SETTLE_TIME
	tr.Stride = tr.Stride or STRIDE * size
	if moving and not tr.WasMoving then
		-- setting off: the first foot to land sounds straight away
		tr.Travelled, tr.SinceLanding, tr.FirstStep = 0, 0, true
	end
	tr.WasMoving = moving
	if moving then
		tr.Travelled += speed * dt
		tr.SinceLanding += speed * dt
	else
		tr.Travelled = 0
	end

	-- Follow each foot's swing and catch the moment it comes down. Each foot is
	-- measured against the ground right under it, so ledges (the path sits higher
	-- than the grass, the spawn pad and shop floor higher still) never look like a
	-- lifted or planted foot. The swing is judged over the last ~1.3 walk cycles only,
	-- so one odd reading is forgotten within a stride.
	local names = FEET[hum.RigType] or FEET[Enum.HumanoidRigType.R15]
	if tr.Rig ~= hum.RigType then
		tr.Rig = hum.RigType
		tr.Feet = {}
		for _, name in ipairs(names) do
			table.insert(tr.Feet, { Name = name, Times = {}, Heights = {}, Armed = false, Last = 0 })
		end
	end
	local window = math.clamp(SWING_CYCLES * 2 * tr.Stride / math.max(speed, 0.1), 0.4, 1.5)
	local landed = nil
	for _, foot in ipairs(tr.Feet) do
		local part = foot.Part
		if not (part and part.Parent == char) then
			part = char:FindFirstChild(foot.Name)
			foot.Part = part
			forgetSwing(foot)
		end
		if part and part:IsA("BasePart") then
			local p = part.Position
			local under = castDown(Vector3.new(p.X, root.Position.Y, p.Z), reach) or ground
			local h = heightAbove(part, under)
			-- a reading no walking foot can give (the ray clipped a ledge) is ignored
			if h > -size and h < 1.6 * size then
				local times, heights = foot.Times, foot.Heights
				table.insert(times, now)
				table.insert(heights, h)
				while times[1] < now - window do
					table.remove(times, 1)
					table.remove(heights, 1)
				end
				local lo, hi = h, h
				for _, v in ipairs(heights) do
					if v < lo then
						lo = v
					elseif v > hi then
						hi = v
					end
				end
				local range = hi - lo
				if range >= MIN_LIFT * size then
					if h >= lo + range * REARM then
						foot.Armed = true
					elseif foot.Armed and h <= lo + range * STRIKE then
						foot.Armed = false
						if not landed and now - foot.Last >= FOOT_GAP then
							foot.Last = now
							landed = under
						end
					end
				else
					foot.Armed = false
				end
			end
		end
	end

	-- Steps go by distance walked, one per stride, and sound on the foot landings:
	-- a landing plays a step unless one played less than 70% of a stride ago (that is
	-- the same footfall, or a misread near a ledge). If no landing is seen within 1.25
	-- strides (R6, feet that don't lift, a missed reading) the step plays anyway. So a
	-- step is never dropped or doubled. The stride length is learnt from the
	-- landings, so it fits any avatar size or animation pack.
	if not moving then
		return
	end
	if landed then
		local since = tr.SinceLanding
		if since > tr.Stride * 0.6 and since < tr.Stride * 1.6 then
			tr.Stride = math.clamp(tr.Stride + (since - tr.Stride) * 0.3, STRIDE * size * 0.5, STRIDE * size * 2)
		end
		tr.SinceLanding = 0
		if tr.FirstStep or tr.Travelled >= tr.Stride * 0.7 then
			step(tr, root, landed, now)
		end
	elseif tr.Travelled >= tr.Stride * 1.25 then
		step(tr, root, ground, now)
	end
end

local function drop(tr)
	for _, tween in pairs(tr.Tweens) do
		tween:Cancel()
	end
	if tr.Emitter then
		tr.Emitter:Destroy()
	end
end

local reported = {}

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	-- Only this player's own character makes footsteps on this client. Other
	-- players' characters are never tracked here; their own clients play theirs.
	local char = localPlayer.Character
	if current and current.Character ~= char then
		drop(current) -- respawned: the old character's sounds go with it
		current = nil
	end
	if char and char.Parent then
		current = current or newTracker(char)
		local ok, err = pcall(update, current, dt, now)
		if not ok and not reported[err] then
			reported[err] = true
			warn("[Footsteps] " .. tostring(err))
		end
	end

	-- no other player's footsteps from Roblox's default sound either
	for _, player in ipairs(Players:GetPlayers()) do
		local other = player.Character
		local root = other and other:FindFirstChild("HumanoidRootPart")
		if root then
			muteDefault(root)
		end
	end
end)
