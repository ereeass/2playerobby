-- Mesa Boardwalk scare, on THIS machine only (both riders run it; nobody else sees it).
-- While the scooter this player rides keeps rolling along the boardwalk, every GAP seconds
-- one ROTTEN plank (a Plank with the Rotten attribute: darker, a little crooked) it has
-- already crossed, just BEHIND it (where the camera sees it), creaks and drops away - dust, chips,
-- chunks tumbling - just to scare them. It's only a look: the plank stays solid, so
-- nobody can fall through, and it's back RESET seconds later. Standing still (or off the
-- boardwalk) pauses the countdown, so nothing happens. Look copied from RottenBridgeFx.

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local GAP_MIN, GAP_MAX = 5, 6    -- seconds of riding between planks
local FIRST        = 1.5         -- seconds of riding before the first one (flat out the
                                 -- whole boardwalk only takes ~5 s)
local MOVING       = 3           -- studs/s: slower than this counts as standing still
local BEHIND_MIN   = 2.6         -- the plank the back wheel has just rolled off...
local BEHIND_MAX   = 6           -- ...so it snaps right behind the scooter, where the camera sees it
local CREAK        = 0.3
local RESET        = 12
local FADE_AFTER, FADE_TIME = 1, 0.9
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local CHIP_COLORS  = { Color3.fromRGB(112, 90, 66), Color3.fromRGB(150, 122, 86), Color3.fromRGB(90, 72, 54) }

local player = Players.LocalPlayer
local walk = workspace:WaitForChild("Mesa Boardwalk")
local deck = walk:WaitForChild("Deck")

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { deck }

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
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
		Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(2, 7),
		SpreadAngle = Vector2.new(180, 180), Drag = 2.5, Acceleration = Vector3.new(0, -3, 0),
		RotSpeed = NumberRange.new(-60, 60), Rotation = NumberRange.new(0, 360),
	})
end

local function woodChips(cf, size, count)
	burst(cf, size, count, {
		Color = ColorSequence.new(CHIP_COLORS[math.random(#CHIP_COLORS)]),
		Size = NumberSequence.new(0.25, 0.1), Transparency = NumberSequence.new(0, 0.6),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(70, 70), Acceleration = Vector3.new(0, -60, 0),
		RotSpeed = NumberRange.new(-300, 300), Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Top,
	})
end

local gone = {}      -- [plank] = true while it's "fallen" here
local crossed = {}   -- planks this scooter has rolled over, this trip

local function drop(plank)
	gone[plank] = true
	local cf0, col0 = plank.CFrame, plank.Color
	-- the long side is across the boardwalk
	local size = plank.Size
	local alongX = size.X >= size.Z
	local W, D = alongX and size.X or size.Z, alongX and size.Z or size.X
	local F = alongX and cf0 or cf0 * CFrame.Angles(0, math.pi / 2, 0)

	-- CREAK: shake, sag, darken, a puff of dust
	sandDust(F, Vector3.new(W, 0.2, D), 6)
	local t0 = os.clock()
	while os.clock() - t0 < CREAK do
		local k = (os.clock() - t0) / CREAK
		plank.CFrame = cf0 * CFrame.new(0, -0.08 * k, 0) * CFrame.Angles(math.rad((math.random() - 0.5) * 4 * k), 0, math.rad((math.random() - 0.5) * 3 * k))
		plank.Color = col0:Lerp(Color3.fromRGB(40, 30, 22), 0.35 * k)
		RunService.Heartbeat:Wait()
	end

	-- SNAP: the plank vanishes here (still solid, so nobody can fall), chunks drop away
	plank.CFrame, plank.Color = cf0, col0
	plank.LocalTransparencyModifier = 1
	local pieces = math.random(2, 3)
	local x = -W / 2
	for k = 1, pieces do
		local w = (k == pieces) and (W / 2 - x) or (W / pieces) * (0.7 + math.random() * 0.6)
		local chunk = localPart({
			Size = Vector3.new(math.max(0.8, w - 0.15), size.Y, D - 0.05), Color = col0,
			Material = plank.Material, Anchored = false, CanCollide = true,
			CFrame = F * CFrame.new(x + w / 2, 0, 0) * CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 10)),
		})
		chunk.MaterialVariant = plank.MaterialVariant
		chunk.CollisionGroup = "KnockedCone"
		chunk.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 6, -6 - math.random() * 6, (math.random() - 0.5) * 6)
		chunk.AssemblyAngularVelocity = Vector3.new((math.random() - 0.5) * 8, (math.random() - 0.5) * 4, (math.random() - 0.5) * 8)
		fadeAndGo(chunk, FADE_AFTER)
		x += w
	end
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

	task.delay(RESET, function()
		if plank.Parent then plank.LocalTransparencyModifier = 0 end
		gone[plank] = nil
	end)
end

local countdown = FIRST
local offFor = 0

RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	local under = chassis and workspace:GetPartBoundsInBox(chassis.CFrame * CFrame.new(0, -1.4, 0), Vector3.new(3, 1.6, 2.5), params)
	if not under or #under == 0 then
		-- off the boardwalk: forget this trip after a moment
		offFor += dt
		if offFor > 3 then crossed = {}; countdown = FIRST end   -- next trip starts fresh
		return
	end
	offFor = 0
	for _, p in ipairs(under) do
		if p.Name == "Plank" and p:GetAttribute("Rotten") then crossed[p] = true end
	end
	local v = chassis.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude < MOVING then return end   -- standing still: nothing
	countdown -= dt
	if countdown > 0 then return end
	countdown = GAP_MIN + math.random() * (GAP_MAX - GAP_MIN)
	-- a plank already crossed and well behind (the way it's heading)
	local heading = Vector3.new(v.X, 0, v.Z).Unit
	local pick = {}
	for p in pairs(crossed) do
		if p.Parent and not gone[p] then
			local back = -(p.Position - chassis.Position):Dot(heading)
			local side = ((p.Position - chassis.Position) + heading * back) * Vector3.new(1, 0, 1)
			if back >= BEHIND_MIN and back <= BEHIND_MAX and side.Magnitude < 8 then table.insert(pick, p) end
		end
	end
	if #pick > 0 then
		task.spawn(drop, pick[math.random(#pick)])
	else
		countdown = 0.3   -- none far enough behind yet: try again in a moment
	end
end)
