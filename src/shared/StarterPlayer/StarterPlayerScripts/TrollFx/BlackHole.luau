--=====================================================================
-- BlackHole   (TrollFx) - BLACK HOLE, as this machine shows it
--
-- On the scooter it was bought onto and nothing else: it stops dead and a black hole tears
-- open ahead of it - a pitch-black middle with a shimmering purple edge, a blazing tilted disc
-- round it, sparks and bits of glowing stuff orbiting faster and faster, sparkles and haze
-- streaming in from all round, chunks of the ground torn up and swirling in, a deep roar. The
-- scooter strains and creeps towards it, then it's dragged in with both riders - spiralling,
-- rolling over and over, glowing purple, a streak behind them - and GULP! Gone. The hole
-- bulges, then slams shut in a flash.
--
-- EVERYTHING here is only this machine's picture. The one scooter the troll was bought onto is
-- moved only on this screen (the server holds it still); nothing else is moved, pushed or
-- touched - the chunks of ground and the sparkles are this machine's own pieces, touching
-- nothing. There is no force, gravity or area of any kind: anyone standing right beside them
-- only watches. The clock is ReplicatedStorage.TrollFx.BlackHoleTimeline (every timing, size
-- and distance); the sounds are ReplicatedStorage.TrollFx.BlackHoleSounds; the shared pieces
-- TrollFx.Kit.
--=====================================================================

local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local fx       = RS:WaitForChild("TrollFx")
local T        = require(fx:WaitForChild("BlackHoleTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local soundsOf = fx:WaitForChild("BlackHoleSounds")
local seq, cseq = Kit.seq, Kit.cseq

-- the look of it
local PURPLE    = Color3.fromRGB(120, 40, 235)
local PINK      = Color3.fromRGB(255, 90, 210)
local ORANGE    = Color3.fromRGB(255, 105, 20)
local HOT       = Color3.fromRGB(255, 230, 160)
local DISC_TILT = math.rad(22)   -- how far its disc is tipped towards whoever watches from behind
local ORBITERS  = 28             -- glowing bits orbiting it
local CHUNKS    = 18             -- bits of ground torn up and swirled in
local CHUNK_TIME = { 0.7, 1.1 }  -- seconds each takes to be sucked in
local HUM_MAX   = 0.9            -- the roar's loudest

local BlackHole = {}

local shows = 0          -- each show's own name for its per-frame step

-- an anchored piece of this machine's picture, touching nothing
local function piece(props)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local UP = CFrame.Angles(0, 0, math.rad(90))   -- a cylinder lying flat (its axis up)

function BlackHole.Play(scooter)
	local start   = scooter:GetAttribute("TrollStart")
	local base    = scooter:GetAttribute("TrollBase")
	local chassis = scooter.PrimaryPart
	if not chassis then return end
	local function clock() return workspace:GetServerTimeNow() - start end

	local riders = Kit.ridersOf(scooter, chassis)
	local hidden = {}
	local pieces = {}          -- this machine's own additions, removed when it is over
	local function own(inst) table.insert(pieces, inst); return inst end
	local function cleanup()
		for _, inst in ipairs(pieces) do if inst.Parent then inst:Destroy() end end
		table.clear(pieces)
	end

	-- long over (this machine only just got here): the server has hidden it already
	if clock() >= T.EXPLODE + 1.5 then
		Kit.hide(scooter, hidden)
		for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
		return
	end

	local pivotFromChassis = chassis.CFrame:ToObjectSpace(scooter:GetPivot())
	local home = Kit.mine()
	local flat = T.Flat(base)
	local holeCF = T.Hole(base)
	local holePos = holeCF.Position
	local models = { scooter, table.unpack(riders) }
	local rng = Random.new(math.floor(start * 1000) % 2147483647)

	-- the ground under them (what the torn-up chunks look like)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { home, table.unpack(models) }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(base.Position, Vector3.new(0, -12, 0), params)
	local groundY = hit and hit.Position.Y or base.Position.Y - 1.5
	local groundColor = hit and hit.Instance:IsA("BasePart") and hit.Instance.Color or Color3.fromRGB(90, 90, 100)
	local groundMat = hit and hit.Instance:IsA("BasePart") and hit.Instance.Material or Enum.Material.SmoothPlastic

	---------------------------------------------------------------- the hole
	-- its disc, tipped towards whoever watches from behind them
	local discCF = holeCF * CFrame.Angles(DISC_TILT, 0, 0)
	local core = own(piece({ Name = "TrollBlackHole", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
		Color = Color3.new(0, 0, 0), Size = Vector3.one * 0.1 }))
	local edge = own(piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = PURPLE, Size = Vector3.one * 0.1 }))
	local outerDisc = own(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PURPLE,
		Transparency = 0.55, Size = Vector3.one * 0.1 }))
	local innerDisc = own(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = ORANGE,
		Transparency = 0.2, Size = Vector3.one * 0.1 }))
	for _, p in ipairs({ core, edge, outerDisc, innerDisc }) do p.Parent = home end
	core.CFrame, edge.CFrame = holeCF, holeCF
	local glow = Instance.new("PointLight")
	glow.Color = PURPLE
	glow.Range = 30
	glow.Brightness = 0
	glow.Parent = edge

	-- glowing bits orbiting it in its disc, the inner ones faster
	local orbiters = {}
	for i = 1, ORBITERS do
		local r = rng:NextNumber(1.5, 3.5)
		local c = r < 2.2 and HOT or (r < 2.9 and ORANGE or (rng:NextNumber() < 0.5 and PINK or PURPLE))
		local p = own(piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = c,
			Size = Vector3.one * rng:NextNumber(0.25, 0.6) }))
		p.Parent = home
		table.insert(orbiters, { part = p, r = r, a = rng:NextNumber(0, math.pi * 2), speed = 7 / r, bob = rng:NextNumber(-0.15, 0.15) })
	end

	-- sparkles and haze streaming in from all round
	local inflow = own(piece({ Name = "TrollHoleInflow", Transparency = 1, Size = Vector3.one * 26, CFrame = holeCF }))
	inflow.Parent = home
	local streams = Instance.new("ParticleEmitter")
	streams.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	streams.Color = cseq(Color3.new(1, 1, 1), PINK)
	streams.LightEmission = 1
	streams.LightInfluence = 0
	streams.Size = seq({ { 0, 0.2 }, { 0.7, 0.6 }, { 1, 0 } })
	streams.Lifetime = NumberRange.new(0.7, 0.9)
	streams.Speed = NumberRange.new(15, 18)
	streams.Shape = Enum.ParticleEmitterShape.Sphere
	streams.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	streams.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	streams.Rate = 0
	streams.Parent = inflow
	local smokeIn = Instance.new("ParticleEmitter")
	smokeIn.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeIn.Color = cseq(Color3.fromRGB(120, 60, 200), Color3.fromRGB(40, 10, 70))
	smokeIn.LightEmission = 0.3
	smokeIn.Size = seq({ { 0, 4 }, { 1, 0.5 } })
	smokeIn.Transparency = seq({ { 0, 1 }, { 0.3, 0.6 }, { 1, 0.9 } })
	smokeIn.Lifetime = NumberRange.new(0.9, 1.1)
	smokeIn.Speed = NumberRange.new(11, 13)
	smokeIn.Rotation = NumberRange.new(0, 360)
	smokeIn.RotSpeed = NumberRange.new(150, 250)
	smokeIn.Shape = Enum.ParticleEmitterShape.Sphere
	smokeIn.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	smokeIn.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	smokeIn.Rate = 0
	smokeIn.Parent = inflow

	-- chunks of the ground round them, torn up and swirled in, one after another
	local chunks = {}
	for _ = 1, CHUNKS do
		local ang = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(3, 11)
		local from = Vector3.new(base.Position.X + math.cos(ang) * dist, groundY + 0.3, base.Position.Z + math.sin(ang) * dist)
		local size = Vector3.new(rng:NextNumber(0.5, 1.4), rng:NextNumber(0.3, 0.7), rng:NextNumber(0.5, 1.4))
		local p = own(piece({ Material = groundMat, Color = groundColor, Size = size, Transparency = 1 }))
		p.Parent = home
		local at = rng:NextNumber(0.4, T.EXPLODE - 0.3)
		table.insert(chunks, { part = p, from = from, size = size, at = at,
			dur = rng:NextNumber(CHUNK_TIME[1], CHUNK_TIME[2]), spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			twist = rng:NextNumber(3, 6) * (rng:NextNumber() < 0.5 and -1 or 1) })
	end

	---------------------------------------------------------------- them
	-- glowing purple as it takes them
	local tints = {}
	for _, m in ipairs(models) do
		local h = own(Instance.new("Highlight"))
		h.Adornee = m
		h.FillColor = PURPLE
		h.OutlineColor = PINK
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = home
		table.insert(tints, h)
	end
	-- a streak behind them as they're dragged in
	local s0 = own(Instance.new("Attachment"))
	s0.Position = Vector3.new(0, -0.5, 0)
	s0.Parent = chassis
	local s1 = own(Instance.new("Attachment"))
	s1.Position = Vector3.new(0, 4.5, 0)
	s1.Parent = chassis
	local streak = own(Instance.new("Trail"))
	streak.Attachment0, streak.Attachment1 = s0, s1
	streak.Color = cseq(PINK, PURPLE)
	streak.Transparency = seq({ { 0, 0.4 }, { 1, 1 } })
	streak.Lifetime = 0.3
	streak.LightInfluence = 0
	streak.LightEmission = 1
	streak.FaceCamera = true
	streak.Enabled = false
	streak.Parent = chassis

	-- its sounds, from the hole
	local sounds = {}
	for _, s in ipairs(soundsOf:GetChildren()) do
		if s:IsA("Sound") then
			local c = s:Clone()
			c.Parent = inflow
			sounds[s.Name] = c
		end
	end

	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	shows += 1
	local step = "TrollBlackHole" .. shows
	local done = false
	local function finish()
		if done then return end
		done = true
		RunService:UnbindFromRenderStep(step)
	end

	-- the hole, drawn at its size and power, spinning
	local function drawHole(t)
		local s = T.Size(t)
		local power = T.Power(t)
		local on = s > 0.01
		local r = T.CORE * s
		core.Size = Vector3.one * math.max(r * 2, 0.05)
		edge.Size = Vector3.one * math.max(r * 2.5, 0.05)
		local spin = CFrame.Angles(0, t * (1.5 + 5 * power), 0)
		outerDisc.Size = Vector3.new(0.12, r * 7, r * 7)
		outerDisc.CFrame = discCF * spin * UP
		innerDisc.Size = Vector3.new(0.18, r * 4.6, r * 4.6)
		innerDisc.CFrame = discCF * spin * UP
		for _, p in ipairs({ core, edge, outerDisc, innerDisc }) do p.LocalTransparencyModifier = on and 0 or 1 end
		innerDisc.Transparency = 0.35 - 0.2 * power
		glow.Brightness = on and (1 + 3 * power) * math.min(s, 1) or 0
		-- the orbiting bits, the inner ones faster, all faster as it feeds
		for _, o in ipairs(orbiters) do
			local a = o.a + t * o.speed * (1 + 2.5 * power)
			local rr = o.r * r
			o.part.CFrame = discCF * CFrame.new(math.cos(a) * rr, o.bob * r, math.sin(a) * rr)
			o.part.LocalTransparencyModifier = on and 0 or 1
		end
		streams.Rate = on and t < T.EXPLODE and 20 + 80 * power or 0
		smokeIn.Rate = on and t < T.EXPLODE and 4 + 14 * power or 0
		if sounds.Hum then sounds.Hum.Volume = HUM_MAX * (0.4 + 0.6 * power) * math.min(s, 1) end
	end

	-- the torn-up chunks: from the ground, spiralling in, shrinking as they go
	local function drawChunks(t)
		for _, c in ipairs(chunks) do
			local k = (t - c.at) / c.dur
			if k <= 0 or k >= 1 or t >= T.EXPLODE + T.COLLAPSE then
				c.part.Transparency = 1
			else
				local e = k ^ 1.8
				local line = c.from:Lerp(holePos, e)
				local a = c.twist * e
				local r = 2 * math.sin(math.pi * e)
				local pos = line + flat.RightVector * math.cos(a) * r + flat.UpVector * math.sin(a) * r
				c.part.Size = c.size * math.max(1 - e * 0.85, 0.1)
				c.part.CFrame = CFrame.new(pos) * CFrame.Angles(c.spin.X * k, c.spin.Y * k, c.spin.Z * k)
				c.part.Transparency = 0
			end
		end
	end

	-- every frame, before the cameras look at it
	RunService:BindToRenderStep(step, Enum.RenderPriority.Camera.Value - 1, function()
		if not (scooter.Parent and chassis.Parent) then finish() return end
		local t = clock()
		if t < 0 then return end

		once("open", function()
			if sounds.Open then sounds.Open:Play() end
			if sounds.Hum then sounds.Hum.Volume = 0; sounds.Hum:Play() end
		end)
		drawHole(t)
		drawChunks(t)

		if t < T.EXPLODE then
			local pose = T.Pose(base, t)
			scooter:PivotTo(pose * pivotFromChassis)
			local pull = T.Pull(t)
			streak.Enabled = pull > 0.05
			local tint = math.max(T.Power(t) * 0.3, pull)
			for _, h in ipairs(tints) do
				h.FillTransparency = 1 - 0.6 * tint
				h.OutlineTransparency = 1 - 0.8 * tint
			end
			return
		end

		-- GULP: swallowed
		once("gulp", function()
			scooter:PivotTo(base * pivotFromChassis)
			Kit.hide(scooter, hidden)
			for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
			streak.Enabled = false
			for _, h in ipairs(tints) do h.Enabled = false end
			if t < T.EXPLODE + 1 and sounds.Gulp then sounds.Gulp:Play() end
		end)
		if t < T.EXPLODE + T.COLLAPSE then return end

		-- slammed shut: a flash, a ring, sparks flung out, GULP!
		once("shut", function()
			if sounds.Hum then TweenService:Create(sounds.Hum, TweenInfo.new(0.3), { Volume = 0 }):Play() end
			if t > T.EXPLODE + T.COLLAPSE + 1 then return end
			local flash = Kit.ball(Color3.fromRGB(245, 220, 255), 2, holePos, 0.05)
			Kit.grow(flash, { Size = Vector3.one * 18, Transparency = 1 }, 0.35)
			local ring = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PINK,
				Transparency = 0.2, Size = Vector3.new(0.3, 3, 3), CFrame = discCF * UP })
			ring.Parent = home
			Kit.grow(ring, { Size = Vector3.new(0.3, 40, 40), Transparency = 1 }, 0.5)
			Debris:AddItem(ring, 0.7)
			local point = piece({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(holePos) })
			point.Parent = home
			Debris:AddItem(point, 3.5)
			Kit.burst(point, 60, {
				Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Color = cseq(Color3.new(1, 1, 1), PURPLE),
				LightEmission = 1, LightInfluence = 0,
				Size = seq({ { 0, 1 }, { 1, 0.1 } }),
				Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(30, 55), Drag = 2.5,
			})
			Kit.burst(point, 18, {
				Texture = "rbxasset://textures/particles/smoke_main.dds",
				Color = cseq(Color3.fromRGB(150, 90, 230), Color3.fromRGB(60, 30, 100)),
				Size = seq({ { 0, 3 }, { 1, 9 } }), Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
				Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(8, 16), Drag = 3,
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), LightInfluence = 0.4,
			})
			Kit.shout(point, "GULP!", cseq(Color3.fromRGB(255, 200, 255), PURPLE), Color3.fromRGB(40, 10, 70))
			if sounds.Collapse then
				local s = sounds.Collapse:Clone()
				s.Parent = point
				s:Play()
			end
		end)
		if t >= T.END then finish() end
	end)

	-- when the scooter goes (the ride ended, or a revive brought a new one), so does
	-- everything this machine added; anyone still riding it is shown again
	local conn
	conn = scooter.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		conn:Disconnect()
		finish()
		Kit.unhide(hidden)
		cleanup()
	end)
	-- the rest goes a little after the show
	task.delay(math.max(start + T.END + 2 - workspace:GetServerTimeNow(), 0), function()
		finish()
		cleanup()
	end)
end

return BlackHole
