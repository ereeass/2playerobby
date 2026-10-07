-- The Lava Monster, run by the SERVER so every player sees and hears the same thing at the same
-- moment. Three things happen on their own timers:
--   Roar       every RoarEvery seconds (random between the two): the jaw drops open, the mouth
--              glows, it roars, then the jaw closes.
--   Fireball   every ThrowEvery seconds: a fireball leaves the lava rock in its raised hand and
--              arcs out into the open sea in front of it, bursting into steam and spray there.
--              The rock in its hand shrinks away and glows back.
--   Splash     every SplashEvery seconds: lava bursts up out of the sea near its feet.
-- The fireballs and lava land only in open water (never on a road); none of it hurts anyone.
-- Tuning: attributes on this script (min,max seconds as a Vector2).
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")
local Sfx          = require(RS:WaitForChild("ObstacleSfx"))

local monster = script.Parent
local head, arms = monster:WaitForChild("Head"), monster:WaitForChild("Arms")
local jaw, glow = head:WaitForChild("Jaw"), head:WaitForChild("MouthGlow")
local rock = arms:WaitForChild("LavaRock")
local water = workspace:WaitForChild("Map"):WaitForChild("Water"):WaitForChild("Water")
local SEA = water.Position.Y + water.Size.Y / 2

local function range(name, a, b)
	local v = script:GetAttribute(name)
	if typeof(v) == "Vector2" then a, b = v.X, v.Y end
	return a + math.random() * (b - a)
end

local LAVA  = Color3.fromRGB(255, 96, 16)
local HOT   = Color3.fromRGB(255, 180, 50)
local FIRE  = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local fx = Instance.new("Folder")
fx.Name = "LavaMonsterFx"
fx.Parent = workspace

-- where things may land: the open sea in front of it (checked clear of roads and islands)
local centre = Vector3.new(monster:GetPivot().Position.X, SEA, monster:GetPivot().Position.Z)
local FRONT_FROM, FRONT_TO = math.rad(235), math.rad(292)
local function seaSpot(r0, r1)
	local a = FRONT_FROM + math.random() * (FRONT_TO - FRONT_FROM)
	local r = r0 + math.random() * (r1 - r0)
	return centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function burst(at, count, props, life)
	local holder = Instance.new("Part")
	holder.Anchored, holder.CanCollide, holder.CanTouch, holder.CanQuery = true, false, false, false
	holder.Transparency, holder.Size, holder.CFrame = 1, Vector3.one, CFrame.new(at)
	holder.Parent = fx
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, life or 4)
	return holder
end

local function blob(pos, size, vel)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.one * size
	b.Material, b.Color = Enum.Material.Neon, LAVA
	b.CanCollide, b.CanTouch, b.CanQuery, b.CastShadow = false, false, false, false
	b.CFrame = CFrame.new(pos)
	b.Parent = fx
	pcall(function() b:SetNetworkOwner(nil) end)
	b.AssemblyLinearVelocity = vel
	return b
end

---------------------------------------------------------------- roar
local jawParts = { jaw }
for _, t in ipairs(head:GetChildren()) do
	if t.Name == "Tooth" and t.Position.Y < jaw.Position.Y + jaw.Size.Y / 2 + 2 then table.insert(jawParts, t) end
end
-- the hinge: the jaw's back top edge (the jaw's front faces the way the head looks)
local hinge = jaw.CFrame * CFrame.new(0, jaw.Size.Y / 2, -jaw.Size.Z / 2)
local rel = {}
for _, p in ipairs(jawParts) do rel[p] = hinge:ToObjectSpace(p.CFrame) end
local glowColor, glowSize = glow.Color, glow.Size
local glowLight = Instance.new("PointLight")
glowLight.Color, glowLight.Range, glowLight.Brightness = LAVA, 30, 0
glowLight.Parent = glow

local OPEN = math.rad(28)
local function setJaw(a)
	local cf = hinge * CFrame.Angles(a, 0, 0)
	for p, r in pairs(rel) do p.CFrame = cf * r end
end
local function roar()
	Sfx.Play("LavaMonsterRoar", glow)
	local t0 = os.clock()
	local HOLD = 2.6
	while true do
		local t = os.clock() - t0
		if t > HOLD + 0.5 then break end
		local k
		if t < 0.3 then k = t / 0.3                       -- opens fast
		elseif t < HOLD then k = 1 + 0.08 * math.sin(t * 30) -- shakes while it roars
		else k = 1 - (t - HOLD) / 0.5 end                  -- closes
		k = math.clamp(k, 0, 1.1)
		setJaw(OPEN * k)
		glow.Color = glowColor:Lerp(HOT, math.min(k, 1))
		glow.Size = glowSize * (1 + 1.5 * math.min(k, 1))
		glowLight.Brightness = 4 * math.min(k, 1)
		RunService.Heartbeat:Wait()
	end
	setJaw(0)
	glow.Color, glow.Size, glowLight.Brightness = glowColor, glowSize, 0
end

---------------------------------------------------------------- fireball
local rockSize = rock.Size
-- the throwing arm: every Arms part on the lava rock's side (the raised right arm), swung
-- about its shoulder (the arm's lowest point, where it meets the body)
local armParts, shoulder = {}, nil
do
	local lowY, sum, n = math.huge, Vector3.zero, 0
	for _, p in ipairs(arms:GetChildren()) do
		if p:IsA("BasePart") and p.Position.X > rock.Position.X - 22 then
			table.insert(armParts, p)
			lowY = math.min(lowY, p.Position.Y)
		end
	end
	for _, p in ipairs(armParts) do
		if p.Position.Y < lowY + 5 then sum += p.Position; n += 1 end
	end
	shoulder = CFrame.new(n > 0 and sum / n or rock.Position)
end
local armRel = {}
for _, p in ipairs(armParts) do armRel[p] = shoulder:ToObjectSpace(p.CFrame) end
local function setArm(axis, angle)
	local cf = shoulder * CFrame.fromAxisAngle(axis, angle)
	for p, r in pairs(armRel) do p.CFrame = cf * r end
end
local function ease(t) return t * t * (3 - 2 * t) end

local BALL = 16   -- the fireball's size

-- a big water splash where something lands in the sea: a crown of spray thrown up and out,
-- droplets raining back down, and a ring of foam spreading over the water
local WATER = Color3.fromRGB(190, 235, 255)
local FOAM  = Color3.fromRGB(245, 252, 255)
local function waterSplash(at, scale)
	scale = scale or 1
	-- the crown: a tall column of spray...
	burst(at + Vector3.new(0, 1, 0), 70, {
		Texture = SMOKE, Color = ColorSequence.new(FOAM, WATER), Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new(5 * scale, 11 * scale), Lifetime = NumberRange.new(0.9, 1.5),
		Speed = NumberRange.new(45 * scale, 75 * scale), SpreadAngle = Vector2.new(14, 14),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -90, 0), Drag = 1,
	}, 4)
	-- ...and a wider sheet thrown out sideways
	burst(at + Vector3.new(0, 1, 0), 50, {
		Texture = SMOKE, Color = ColorSequence.new(FOAM, WATER), Transparency = NumberSequence.new(0.2, 1),
		Size = NumberSequence.new(4 * scale, 8 * scale), Lifetime = NumberRange.new(0.7, 1.1),
		Speed = NumberRange.new(30 * scale, 50 * scale), SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -80, 0), Drag = 1.5,
	}, 4)
	-- droplets: little balls of water flying out and falling back in
	for _ = 1, math.floor(18 * scale) do
		local a = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a)) * (10 + math.random() * 22) * scale
		local d = Instance.new("Part")
		d.Shape = Enum.PartType.Ball
		d.Size = Vector3.one * (0.8 + math.random() * 1.4) * scale
		d.Material, d.Color, d.Transparency = Enum.Material.Glass, WATER, 0.25
		d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = false, false, false, false
		d.CFrame = CFrame.new(at + Vector3.new(0, 2, 0))
		d.Parent = fx
		pcall(function() d:SetNetworkOwner(nil) end)
		d.AssemblyLinearVelocity = out + Vector3.new(0, (40 + math.random() * 35) * scale, 0)
		Debris:AddItem(d, 3)
	end
	-- the ring of foam spreading out over the sea, and a second one after it
	for i, delay in ipairs({ 0, 0.25 }) do
		task.delay(delay, function()
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Material, ring.Color, ring.Transparency = Enum.Material.SmoothPlastic, FOAM, 0.15
			ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = true, false, false, false, false
			ring.Size = Vector3.new(0.3, 6 * scale, 6 * scale)
			ring.CFrame = CFrame.new(at + Vector3.new(0, 0.2 + i * 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = fx
			local grow = (i == 1 and 60 or 42) * scale
			TweenService:Create(ring, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.3, grow, grow), Transparency = 1 }):Play()
			Debris:AddItem(ring, 1.7)
		end)
	end
end
local function throw()
	local to = seaSpot(60, 100)
	local flat = ((to - shoulder.Position) * Vector3.new(1, 0, 1)).Unit
	local axis = flat:Cross(Vector3.yAxis).Unit      -- + swings the arm back, - swings it forward
	local BACK, FORWARD = math.rad(38), math.rad(-42)
	-- wind up: the arm draws back, the rock in its hand flaring
	local t0 = os.clock()
	while os.clock() - t0 < 0.7 do
		local k = ease((os.clock() - t0) / 0.7)
		setArm(axis, BACK * k)
		rock.Size = rockSize * (1 + 0.25 * k)
		RunService.Heartbeat:Wait()
	end
	-- the throw: a fast swing forward, the ball leaves the hand near the top of it
	local released = false
	t0 = os.clock()
	local from
	while os.clock() - t0 < 0.28 do
		local k = (os.clock() - t0) / 0.28
		setArm(axis, BACK + (FORWARD - BACK) * (k * k))
		if not released and k > 0.55 then released, from = true, rock.Position end
		RunService.Heartbeat:Wait()
	end
	setArm(axis, FORWARD)
	from = from or rock.Position
	-- the rock in its hand has gone with the throw and grows back
	rock.Size = rockSize * 0.2
	TweenService:Create(rock, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = rockSize }):Play()
	-- the arm settles back to where it rests
	task.spawn(function()
		local s0 = os.clock()
		while os.clock() - s0 < 0.9 do
			setArm(axis, FORWARD * (1 - ease((os.clock() - s0) / 0.9)))
			RunService.Heartbeat:Wait()
		end
		setArm(axis, 0)
	end)

	local T = 2.4
	local g = workspace.Gravity
	local vel = (to - from) / T + Vector3.new(0, 0.5 * g * T, 0)
	burst(from, 24, {
		Texture = FIRE, Color = ColorSequence.new(HOT, LAVA), LightEmission = 1,
		Size = NumberSequence.new(10, 2), Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(14, 28), SpreadAngle = Vector2.new(180, 180),
	})
	local ball = blob(from, BALL, vel)
	local crust = Instance.new("Part")   -- a dark cracked shell round the glow
	crust.Shape = Enum.PartType.Ball
	crust.Size = Vector3.one * BALL * 1.02
	crust.Material, crust.Color, crust.Transparency = Enum.Material.CrackedLava, Color3.fromRGB(80, 36, 26), 0.35
	crust.CanCollide, crust.CanTouch, crust.CanQuery, crust.CastShadow, crust.Massless = false, false, false, false, true
	crust.CFrame = ball.CFrame
	local w = Instance.new("WeldConstraint"); w.Part0, w.Part1 = ball, crust; w.Parent = crust
	crust.Parent = ball
	local f = Instance.new("Fire"); f.Size = 25; f.Heat = 12; f.Color = LAVA; f.SecondaryColor = Color3.fromRGB(255, 40, 0); f.Parent = ball
	local l = Instance.new("PointLight"); l.Range = 50; l.Brightness = 4; l.Color = LAVA; l.Parent = ball
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, BALL * 0.35, 0); a0.Parent = ball
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -BALL * 0.35, 0); a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(HOT, LAVA)
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = 0.7
	trail.Parent = ball
	local t1 = os.clock()
	while ball.Parent and ball.Position.Y > SEA and os.clock() - t1 < 6 do RunService.Heartbeat:Wait() end
	local hit = Vector3.new(ball.Position.X, SEA, ball.Position.Z)
	ball:Destroy()
	-- into the sea: a big spray, steam, a hiss
	local h = burst(hit + Vector3.new(0, 1, 0), 60, {
		Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)), Transparency = NumberSequence.new(0.2, 1),
		Size = NumberSequence.new(8, 26), Lifetime = NumberRange.new(1.4, 2.6), Speed = NumberRange.new(12, 28),
		SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 4, 0),
	}, 5)
	Sfx.Play("FireballSplash", h)
	waterSplash(hit, 1)
	burst(hit + Vector3.new(0, 1, 0), 45, {
		Texture = FIRE, Color = ColorSequence.new(HOT, LAVA), LightEmission = 0.8,
		Size = NumberSequence.new(6, 1), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(50, 50), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -60, 0),
	})
end

---------------------------------------------------------------- lava splash
local function splash()
	local at = seaSpot(28, 48)
	local h = burst(at + Vector3.new(0, 1, 0), 50, {
		Texture = FIRE, Color = ColorSequence.new(HOT, LAVA), LightEmission = 1,
		Size = NumberSequence.new(6, 1), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(30, 55),
		SpreadAngle = Vector2.new(22, 22), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -70, 0),
	}, 5)
	Sfx.Play("LavaSplash", h)
	burst(at + Vector3.new(0, 1, 0), 25, {
		Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(90, 80, 80)), Transparency = NumberSequence.new(0.3, 1),
		Size = NumberSequence.new(6, 18), Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Top,
	})
	-- a spray of lava blobs thrown up that drop back into the sea
	for _ = 1, 10 do
		local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 18
		local b = blob(at + Vector3.new(0, 1, 0), 1.2 + math.random() * 1.8, dir + Vector3.new(0, 45 + math.random() * 30, 0))
		Debris:AddItem(b, 4)
	end
end

---------------------------------------------------------------- the timers
local function every(name, a, b, first, fn)
	task.spawn(function()
		task.wait(first)
		while monster.Parent do
			local ok, err = pcall(fn)
			if not ok then warn("[LavaMonster] " .. name .. ": " .. tostring(err)) end
			task.wait(range(name, a, b))
		end
	end)
end
every("RoarEvery",   22, 34, 6, roar)
every("ThrowEvery",  7,  11, 2, throw)
every("SplashEvery", 12, 20, 9, splash)
