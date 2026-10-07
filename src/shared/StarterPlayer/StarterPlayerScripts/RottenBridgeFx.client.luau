-- The rotten bridge from Checkpoint 2 (planks tagged "RottenPlank") collapses behind the
-- scooter THIS player rides, on this machine only. Both riders run this and see the same
-- scooter, so the two of them see it go; nobody else does, and it's back for everyone
-- RESET seconds later.
--   CREAK  the plank the scooter rolls onto shakes, darkens, and puffs a little dust
--   SNAP   BREAK_DELAY later it breaks: chunks tumble down, splinters fly, sand dust and
--          wood chips burst out. It's hidden and not solid here, so on the driver's
--          machine (which moves the scooter) anything still on it drops through.
-- BREAK_DELAY is set so at full throttle the back wheel is already off a plank when it
-- goes (~0.24 s at top speed): flat out you just make it, slower and you fall.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local TAG          = "RottenPlank"
local BREAK_DELAY  = 0.35 * 1.25   -- 1.25x slower collapse
local RESET        = 6
local FADE_AFTER   = 1
local FADE_TIME    = 0.9
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local CHIP_COLORS  = { Color3.fromRGB(112, 90, 66), Color3.fromRGB(150, 122, 86), Color3.fromRGB(90, 72, 54) }

local player = Players.LocalPlayer
local state = {}      -- [plank] = "creak" | "gone"

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local function refresh() params.FilterDescendantsInstances = CollectionService:GetTagged(TAG) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(refresh)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(refresh)
refresh()

local function plankOf(part)
	local m = part:FindFirstAncestorOfClass("Model")
	while m and not CollectionService:HasTag(m, TAG) do m = m:FindFirstAncestorOfClass("Model") end
	return m
end

local function localPart(props)
	local p = Instance.new("Part")
	p.Anchored = true p.CanCollide = false p.CanTouch = false p.CanQuery = false p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	p.Parent = workspace
	return p
end

local function fadeAndGo(p, delay)
	task.delay(delay, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(FADE_TIME), { Transparency = 1 }):Play()
			Debris:AddItem(p, FADE_TIME + 0.1)
		end
	end)
end

-- a burst of particles at a spot, then the holder cleans itself up
local function burst(cf, size, count, props)
	local holder = localPart({ Size = size, Transparency = 1, CFrame = cf })
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, 3)
end

local function sandDust(cf, size, count)
	burst(cf, size, count, {
		Texture = DUST_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(214, 192, 148), Color3.fromRGB(180, 160, 124)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(2, 7),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2.5,
		Acceleration = Vector3.new(0, -3, 0),
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
	})
end

local function woodChips(cf, size, count)
	burst(cf, size, count, {
		Color = ColorSequence.new(CHIP_COLORS[math.random(#CHIP_COLORS)]),
		Size = NumberSequence.new(0.25, 0.1),
		Transparency = NumberSequence.new(0, 0.6),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -60, 0),
		RotSpeed = NumberRange.new(-300, 300),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Top,
	})
end

-- the bridge-fall sound: its crack comes 0.39 s in, so started SOUND_LEAD after the creak
-- begins it lands on the snap (BREAK_DELAY). Quiet, and never more than one every FALL_GAP seconds.
local FALL_SOUND, FALL_VOLUME, FALL_GAP = "rbxassetid://74371701057547", 0.22, 0.3
local SOUND_LEAD = BREAK_DELAY - 0.35
local lastFall = 0
local function fallSound(at)
	if os.clock() - lastFall < FALL_GAP then return end
	lastFall = os.clock()
	local holder = localPart({ Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = at })
	local snd = Instance.new("Sound")
	snd.SoundId = FALL_SOUND; snd.Volume = FALL_VOLUME
	snd.RollOffMode = Enum.RollOffMode.InverseTapered; snd.RollOffMinDistance = 8; snd.RollOffMaxDistance = 60
	snd.Parent = holder
	snd:Play()
	Debris:AddItem(holder, 2)
end

local function collapse(plank)
	state[plank] = "creak"
	local board = plank.PrimaryPart or plank:FindFirstChild("Board")
	local parts = {}
	for _, p in ipairs(plank:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, { part = p, cf = p.CFrame, color = p.Color, collide = p.CanCollide }) end
	end
	local F, W, D = board.CFrame, board.Size.X, board.Size.Z
	task.delay(SOUND_LEAD, fallSound, F)

	-- CREAK: shake, darken, a puff of dust out of the cracks
	sandDust(F, Vector3.new(W, 0.2, D), 6)
	local t0 = os.clock()
	while os.clock() - t0 < BREAK_DELAY do
		local k = (os.clock() - t0) / BREAK_DELAY
		local j = CFrame.new(0, -0.06 * k, 0) * CFrame.Angles(math.rad((math.random() - 0.5) * 4 * k), 0, math.rad((math.random() - 0.5) * 3 * k))
		for _, e in ipairs(parts) do
			e.part.CFrame = e.cf * j
			if e.part == board then e.part.Color = e.color:Lerp(Color3.fromRGB(40, 30, 22), 0.35 * k) end
		end
		RunService.Heartbeat:Wait()
	end

	-- SNAP: hide the real plank here, drop the pieces, dust and chips everywhere
	state[plank] = "gone"
	for _, e in ipairs(parts) do
		e.part.CFrame = e.cf
		e.part.Color = e.color
		e.part.LocalTransparencyModifier = 1
		e.part.CanCollide = false
	end
	local pieces = math.random(2, 3)
	local x = -W / 2
	for k = 1, pieces do
		local w = (k == pieces) and (W / 2 - x) or (W / pieces) * (0.7 + math.random() * 0.6)
		local chunk = localPart({
			Size = Vector3.new(math.max(0.8, w - 0.15), board.Size.Y, D - 0.05), Color = board.Color,
			Material = Enum.Material.Plastic, Anchored = false, CanCollide = true,
			CFrame = F * CFrame.new(x + w / 2, 0, 0) * CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 10)),
		})
		chunk.MaterialVariant = board.MaterialVariant
		chunk.CollisionGroup = "KnockedCone"
		chunk.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 6, -6 - math.random() * 6, (math.random() - 0.5) * 6)
		chunk.AssemblyAngularVelocity = Vector3.new((math.random() - 0.5) * 8, (math.random() - 0.5) * 4, (math.random() - 0.5) * 8)
		fadeAndGo(chunk, FADE_AFTER)
		x += w
	end
	-- splinters flying up
	for k = 1, 7 do
		local s = localPart({
			Size = Vector3.new(0.12, 0.12, 0.6 + math.random() * 0.9), Color = CHIP_COLORS[math.random(#CHIP_COLORS)],
			Anchored = false, CanCollide = true,
			CFrame = F * CFrame.new((math.random() - 0.5) * W, 0.3, (math.random() - 0.5) * D) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
		})
		s.CollisionGroup = "KnockedCone"
		s.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 16, 8 + math.random() * 12, (math.random() - 0.5) * 16)
		s.AssemblyAngularVelocity = Vector3.new(math.random() * 20, math.random() * 20, math.random() * 20)
		fadeAndGo(s, FADE_AFTER * 0.6)
	end
	sandDust(F, Vector3.new(W, 0.3, D), 24)
	woodChips(F, Vector3.new(W, 0.2, D), 30)

	-- back for this player later
	task.delay(RESET, function()
		for _, e in ipairs(parts) do
			if e.part.Parent then
				e.part.LocalTransparencyModifier = 0
				e.part.CanCollide = e.collide
			end
		end
		state[plank] = nil
	end)
end

RunService.Heartbeat:Connect(function()
	local chassis = myChassis()
	if not chassis then return end
	-- the planks right under the scooter start to go
	for _, part in ipairs(workspace:GetPartBoundsInBox(chassis.CFrame * CFrame.new(0, -1.4, 0), Vector3.new(3, 1.6, 2.5), params)) do
		local plank = plankOf(part)
		if plank and not state[plank] then task.spawn(collapse, plank) end
	end
end)
