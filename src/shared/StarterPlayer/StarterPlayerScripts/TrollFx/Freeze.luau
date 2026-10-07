--=====================================================================
-- Freeze   (TrollFx) - FREEZE PLAYERS, as this machine shows it
--
-- Explode Players with ice instead of a bomb, on the scooter it was bought onto and nothing
-- else: it stops dead where it is, frost races across the ground and a block of ice grows up
-- round the scooter and both riders (sized to them, so nobody pokes out), with crystals at
-- its foot and corners, cold mist rolling off it and a glint inside. They hold there, frozen
-- stiff (their animations stop), until the ice strains - cracks spread over it, it creaks and
-- trembles harder and harder - and shatters: shards flying, ice dust, a frosty shockwave,
-- CRACK! - and they are gone with it. Nothing is launched: it never leaves its spot. The
-- clock is ReplicatedStorage.TrollFx.FreezeTimeline, from the server's start time; the sounds
-- are ReplicatedStorage.TrollFx.FreezeSounds; the shared pieces TrollFx.Kit. Everything here
-- is this machine's own picture, and all of it is removed when the show is over.
--=====================================================================

local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local fx     = RS:WaitForChild("TrollFx")
local T      = require(fx:WaitForChild("FreezeTimeline"))
local Kit    = require(fx:WaitForChild("Kit"))
local soundsOf = fx:WaitForChild("FreezeSounds")
local seq, cseq = Kit.seq, Kit.cseq

-- the look of it
local PAD        = 0.9      -- studs of ice round the scooter and riders on every side
local MAX_SIDE   = 16       -- studs: never bigger than this (a stray part can't blow it up)
local ICE        = Color3.fromRGB(176, 224, 255)
local ICE_INNER  = Color3.fromRGB(214, 240, 255)
local FROST      = Color3.fromRGB(236, 248, 255)
local CRACK_COL  = Color3.fromRGB(248, 253, 255)
local TINT       = Color3.fromRGB(140, 205, 255)   -- the riders and scooter, frozen
local CRYSTALS   = 14       -- ice crystals round its foot and top corners
local CRACK_RUNS = 9        -- cracks spreading over its faces
local SHARDS     = 34       -- pieces it breaks into

local Freeze = {}

local shows = 0          -- each show's own name for its per-frame step

-- an anchored piece of this machine's picture, touching nothing
local function piece(class, props)
	local p = Instance.new(class or "Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

-- the box round the scooter and its riders, in the chassis' own space: its middle and size
local function boundsOf(chassis, models)
	local inv = chassis.CFrame:Inverse()
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, m in ipairs(models) do
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.95 and p.Size.Magnitude < 25 then
				local cf, h = inv * p.CFrame, p.Size / 2
				for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
					local c = cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
					lo = lo:Min(c)
					hi = hi:Max(c)
				end end end
			end
		end
	end
	if lo.X > hi.X then   -- nothing to measure: a scooter-and-riders sized block
		lo, hi = Vector3.new(-2, -1.5, -4), Vector3.new(2, 6, 4)
	end
	lo -= Vector3.one * PAD
	hi += Vector3.one * PAD
	local size = (hi - lo):Min(Vector3.one * MAX_SIDE)
	local mid = (lo + hi) / 2
	return mid, size, lo.Y
end

-- a crack's path over one face of the box: segments from a random point, zig-zagging on
local function crackPath(mid, size, rng)
	local faces = {
		{ n = Vector3.xAxis,  u = Vector3.zAxis, v = Vector3.yAxis, d = size.X / 2, hu = size.Z / 2, hv = size.Y / 2 },
		{ n = -Vector3.xAxis, u = Vector3.zAxis, v = Vector3.yAxis, d = size.X / 2, hu = size.Z / 2, hv = size.Y / 2 },
		{ n = Vector3.zAxis,  u = Vector3.xAxis, v = Vector3.yAxis, d = size.Z / 2, hu = size.X / 2, hv = size.Y / 2 },
		{ n = -Vector3.zAxis, u = Vector3.xAxis, v = Vector3.yAxis, d = size.Z / 2, hu = size.X / 2, hv = size.Y / 2 },
		{ n = Vector3.yAxis,  u = Vector3.xAxis, v = Vector3.zAxis, d = size.Y / 2, hu = size.X / 2, hv = size.Z / 2 },
	}
	local f = faces[rng:NextInteger(1, #faces)]
	local a, b = rng:NextNumber(-0.6, 0.6) * f.hu, rng:NextNumber(-0.5, 0.6) * f.hv
	local ang = rng:NextNumber(0, math.pi * 2)
	local segs = {}
	for _ = 1, rng:NextInteger(3, 5) do
		local len = rng:NextNumber(0.7, 1.7)
		local na = math.clamp(a + math.cos(ang) * len, -f.hu + 0.2, f.hu - 0.2)
		local nb = math.clamp(b + math.sin(ang) * len, -f.hv + 0.2, f.hv - 0.2)
		local p0 = mid + f.n * (f.d + 0.03) + f.u * a + f.v * b
		local p1 = mid + f.n * (f.d + 0.03) + f.u * na + f.v * nb
		if (p1 - p0).Magnitude > 0.15 then table.insert(segs, { from = p0, to = p1, n = f.n }) end
		a, b = na, nb
		ang += rng:NextNumber(-0.9, 0.9)
	end
	return segs
end

-- the riders' animations: stopped (frozen stiff) and later given back
local function stopAnims(riders, rec)
	for _, ch in ipairs(riders) do
		local hum = ch:FindFirstChildOfClass("Humanoid")
		local anim = hum and hum:FindFirstChildOfClass("Animator")
		if anim then
			for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
				if track.Speed ~= 0 then
					if rec[track] == nil then rec[track] = track.Speed end
					track:AdjustSpeed(0)
				end
			end
		end
	end
end
local function startAnims(rec)
	for track, speed in pairs(rec) do
		pcall(function() if track.IsPlaying then track:AdjustSpeed(speed) end end)
	end
	table.clear(rec)
end

-- the ice breaking apart at `cf` (the block's middle): shards, ice dust, frost, CRACK!
local function shatter(cf, size, groundY, shatterSound, rng)
	local pos = cf.Position
	local home = Kit.mine()

	-- a cold white flash
	local flash = Kit.ball(Color3.fromRGB(225, 245, 255), 3, pos, 0.1)
	Kit.grow(flash, { Size = Vector3.one * (size.Magnitude * 1.6), Transparency = 1 }, 0.4)

	-- a frosty shockwave racing out along the ground
	local ring = piece("Part", {
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(190, 235, 255),
		Transparency = 0.25, Size = Vector3.new(0.3, 4, 4),
		CFrame = cf * CFrame.new(0, groundY + 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	ring.Parent = home
	Kit.grow(ring, { Size = Vector3.new(0.3, 40, 40), Transparency = 1 }, 0.6)
	Debris:AddItem(ring, 0.8)

	-- the block in pieces, flying out and tumbling down
	for _ = 1, SHARDS do
		local wedge = rng:NextNumber() < 0.55
		local s = piece(wedge and "WedgePart" or "Part", {
			Material = rng:NextNumber() < 0.5 and Enum.Material.Glass or Enum.Material.Ice,
			Color = rng:NextNumber() < 0.5 and ICE or ICE_INNER,
			Transparency = rng:NextNumber(0.15, 0.4),
			Reflectance = 0.1,
			Size = Vector3.new(rng:NextNumber(0.3, 1.2), rng:NextNumber(0.5, 1.8), rng:NextNumber(0.3, 1.4)),
		})
		s.Anchored = false
		local off = Vector3.new(rng:NextNumber(-0.5, 0.5) * size.X, rng:NextNumber(-0.5, 0.5) * size.Y, rng:NextNumber(-0.5, 0.5) * size.Z)
		local at = cf * off
		s.CFrame = CFrame.new(at) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		s.Parent = home
		local dir = at - pos
		dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.yAxis
		s.AssemblyLinearVelocity = dir * rng:NextNumber(16, 34) + Vector3.new(0, rng:NextNumber(10, 22), 0)
		s.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 18
		task.delay(1.1, function()
			if s.Parent then TweenService:Create(s, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
		end)
		Debris:AddItem(s, 1.8)
	end

	-- ice dust, glittering frost and snowflakes, from the middle
	local point = piece("Part", { Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	point.Parent = home
	Debris:AddItem(point, 3.5)
	Kit.burst(point, 28, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = cseq(Color3.fromRGB(240, 250, 255), Color3.fromRGB(190, 225, 250)),
		Size = seq({ { 0, 3 }, { 1, 11 } }), Transparency = seq({ { 0, 0.25 }, { 0.7, 0.65 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(10, 20), Drag = 3,
		Acceleration = Vector3.new(0, -2, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.6,
	})
	Kit.burst(point, 70, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = cseq(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 210, 255)),
		LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 0.7 }, { 1, 0.1 } }),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(30, 60), Drag = 2.5,
		Acceleration = Vector3.new(0, -35, 0),
	})
	Kit.burst(point, 24, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = cseq(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 240, 255)),
		LightEmission = 0.6, LightInfluence = 0,
		Size = seq({ { 0, 1.4 }, { 1, 0 } }),
		Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(6, 14), Drag = 1.5,
		Acceleration = Vector3.new(0, -6, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 225, 255)
	light.Range = 40
	light.Brightness = 8
	light.Parent = point
	TweenService:Create(light, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()

	Kit.shout(point, "CRACK!", cseq(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 205, 255)), Color3.fromRGB(16, 48, 96))

	if shatterSound then
		local s = shatterSound:Clone()
		s.Parent = point
		s:Play()
	end
end

function Freeze.Play(scooter)
	local start   = scooter:GetAttribute("TrollStart")
	local base    = scooter:GetAttribute("TrollBase")
	local chassis = scooter.PrimaryPart
	if not chassis then return end
	local function clock() return workspace:GetServerTimeNow() - start end

	local riders = Kit.ridersOf(scooter, chassis)
	local hidden = {}
	local anims  = {}
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
	local rng = Random.new(math.floor(start * 1000) % 2147483647)   -- the same cracks on every screen

	-- the block's box, in the chassis' space (the scooter and both riders, and some)
	local models = { scooter, table.unpack(riders) }
	local mid, size, lowY = boundsOf(chassis, models)
	local groundY = lowY + PAD - 0.05   -- the wheels' underside: where the frost spreads
	local home = Kit.mine()

	-- everything below is placed every frame at the block's pose: rel (in the chassis' space)
	local placed = {}   -- { part, rel }
	local function place(p, rel)
		table.insert(placed, { p, rel })
		return p
	end

	-- the block: a glassy shell, a frostier core, crisp white edges
	local shell = own(piece("Part", {
		Name = "TrollIce", Material = Enum.Material.Glass, Color = ICE,
		Transparency = 0.42, Reflectance = 0.12, Size = size,
	}))
	local core = own(piece("Part", {
		Name = "TrollIceCore", Material = Enum.Material.Ice, Color = ICE_INNER,
		Transparency = 0.78, Size = size - Vector3.one * 0.3,
	}))
	local edges = Instance.new("SelectionBox")
	edges.Adornee = shell
	edges.Color3 = FROST
	edges.LineThickness = 0.06
	edges.Transparency = 0.35
	edges.SurfaceTransparency = 1
	edges.Parent = shell
	shell.Parent, core.Parent = home, home

	-- mist and glitter off its sides, a cold glow inside
	local aura = own(piece("Part", { Name = "TrollIceAura", Transparency = 1, Size = size }))
	aura.Parent = home
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = cseq(FROST, Color3.fromRGB(200, 230, 250))
	mist.Size = seq({ { 0, 1.2 }, { 1, 4.5 } })
	mist.Transparency = seq({ { 0, 1 }, { 0.2, 0.7 }, { 1, 1 } })
	mist.Lifetime = NumberRange.new(1.5, 2.6)
	mist.Speed = NumberRange.new(0.4, 1.4)
	mist.Acceleration = Vector3.new(0, -1.6, 0)   -- cold mist sinks
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-20, 20)
	mist.LightInfluence = 0.7
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	mist.Rate = 0
	mist.Parent = aura
	local glitter = Instance.new("ParticleEmitter")
	glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glitter.Color = cseq(Color3.new(1, 1, 1), Color3.fromRGB(160, 220, 255))
	glitter.LightEmission = 1
	glitter.LightInfluence = 0
	glitter.Size = seq({ { 0, 0.35 }, { 0.5, 0.25 }, { 1, 0 } })
	glitter.Lifetime = NumberRange.new(0.5, 1)
	glitter.Speed = NumberRange.new(0.1, 0.4)
	glitter.Shape = Enum.ParticleEmitterShape.Box
	glitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	glitter.Rate = 0
	glitter.Parent = aura
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(150, 215, 255)
	glow.Range = 16
	glow.Brightness = 0
	glow.Parent = aura

	-- frost spreading over the ground round its foot
	local frostD = math.max(size.X, size.Z) * 1.45
	local frost = own(piece("Part", {
		Name = "TrollFrost", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Snow, Color = FROST,
		Transparency = 0.2, Size = Vector3.new(0.1, 0.1, 0.1),
	}))
	frost.Parent = home
	local frostRel = CFrame.new(mid.X, groundY + 0.04, mid.Z) * CFrame.Angles(0, 0, math.rad(90))
	place(frost, frostRel)

	-- crystals jutting out round its foot and from its top corners, each growing in its turn
	local crystals = {}
	local half = size / 2
	for i = 1, CRYSTALS do
		local top = i > CRYSTALS - 4
		local root, outward
		if top then
			local k = i - (CRYSTALS - 4)
			local sx, sz = (k % 2 == 0) and 1 or -1, (k > 2) and 1 or -1
			root = mid + Vector3.new(sx * half.X * 0.85, half.Y * 0.9, sz * half.Z * 0.85)
			outward = Vector3.new(sx * 0.6, 1, sz * 0.6).Unit
		else
			local ang = (i / (CRYSTALS - 4)) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
			local dx, dz = math.cos(ang), math.sin(ang)
			local k = 1 / math.max(math.abs(dx) / half.X, math.abs(dz) / half.Z)   -- onto the block's edge
			root = Vector3.new(mid.X + dx * k, groundY, mid.Z + dz * k)
			outward = Vector3.new(dx, rng:NextNumber(0.9, 1.6), dz).Unit
		end
		local len = rng:NextNumber(1.2, 2.4) * (top and 0.8 or 1)
		local w = rng:NextNumber(0.35, 0.6)
		local c = own(piece("Part", {
			Name = "TrollCrystal", Material = Enum.Material.Glass, Color = ICE,
			Transparency = 0.2, Reflectance = 0.15, Size = Vector3.new(w, 0.05, w),
		}))
		c.Parent = home
		-- up along `outward`, turned a little on itself
		local look = CFrame.lookAt(root, root + outward) * CFrame.Angles(-math.pi / 2, 0, 0)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		table.insert(crystals, { part = c, root = look, len = len, w = w, at = rng:NextNumber(0.15, 0.85) })
	end

	-- cracks, laid out now and drawn in as it strains
	local cracks = {}
	for r = 1, CRACK_RUNS do
		local startAt = (r - 1) / CRACK_RUNS * 0.75
		for i, sg in ipairs(crackPath(mid, size, rng)) do
			local line = own(piece("Part", {
				Name = "TrollCrack", Material = Enum.Material.Neon, Color = CRACK_COL,
				Transparency = 1, Size = Vector3.new(0.05, 0.03, 0.08),
			}))
			line.Parent = home
			table.insert(cracks, { part = line, seg = sg, at = startAt + (i - 1) * 0.07 })
		end
	end

	-- the scooter and both riders tinted icy as the ice takes them
	local tints = {}
	for _, m in ipairs(models) do
		local h = own(Instance.new("Highlight"))
		h.Adornee = m
		h.FillColor = TINT
		h.OutlineColor = FROST
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = home
		table.insert(tints, h)
	end

	-- its sounds, from the block
	local sounds = {}
	for _, s in ipairs(soundsOf:GetChildren()) do
		if s:IsA("Sound") then
			local c = s:Clone()
			c.Parent = aura
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
	local step = "TrollFreeze" .. shows
	local done = false
	local function finish()
		if done then return end
		done = true
		RunService:UnbindFromRenderStep(step)
	end

	-- every frame, before the cameras look at it
	RunService:BindToRenderStep(step, Enum.RenderPriority.Camera.Value - 1, function()
		if not (scooter.Parent and chassis.Parent) then finish() return end
		local t = clock()
		if t < 0 then return end

		if t >= T.EXPLODE then
			-- the ice shatters, and the scooter and its riders are gone with it
			once("shatter", function()
				scooter:PivotTo(base * pivotFromChassis)
				Kit.hide(scooter, hidden)
				for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
				local cf = base * CFrame.new(mid)
				for _, inst in ipairs(pieces) do
					if inst ~= aura and inst.Parent then inst:Destroy() end
				end
				mist.Rate, glitter.Rate, glow.Brightness = 0, 0, 0
				if sounds.Creak then sounds.Creak:Stop() end
				if t < T.EXPLODE + 1.5 then
					shatter(cf, size, groundY - mid.Y, sounds.Shatter, rng)
				end
			end)
			finish()
			return
		end

		local pose = T.Pose(base, t)
		scooter:PivotTo(pose * pivotFromChassis)
		local g = T.Grow(t)
		local crack = T.Crack(t)

		once("freeze", function()
			if sounds.Freeze then sounds.Freeze:Play() end
			mist:Emit(14)
		end)
		if t >= T.FROZEN then
			once("set", function() glitter:Emit(30) end)
		end
		if t >= T.CRACK then
			once("creak", function() if sounds.Creak then sounds.Creak:Play() end end)
		end
		if g > 0.25 then stopAnims(riders, anims) end   -- frozen stiff

		-- the block grows from the ground up round them
		local h = math.max(size.Y * g, 0.05)
		local blockRel = CFrame.new(mid.X, mid.Y - size.Y / 2 + h / 2, mid.Z)
		shell.Size = Vector3.new(size.X, h, size.Z)
		core.Size = Vector3.new(size.X - 0.3, math.max(h - 0.3, 0.05), size.Z - 0.3)
		shell.CFrame = pose * blockRel
		core.CFrame = shell.CFrame
		aura.Size = shell.Size
		aura.CFrame = shell.CFrame
		-- straining: whiter, cloudier
		shell.Transparency = 0.42 + 0.1 * crack
		core.Transparency = 0.78 - 0.2 * crack

		mist.Rate = 16 * g
		glitter.Rate = 10 * g
		glow.Brightness = 1.6 * g + 1.2 * crack

		-- the frost spreading out over the ground, quicker than the ice rises
		local fg = math.clamp(t / (T.FROZEN * 0.6), 0, 1)
		frost.Size = Vector3.new(0.1, frostD * fg + 0.1, frostD * fg + 0.1)

		for _, cr in ipairs(crystals) do
			local k = math.clamp((g - cr.at) / 0.3, 0, 1)
			local l = math.max(cr.len * k, 0.05)
			cr.part.Size = Vector3.new(cr.w * (0.4 + 0.6 * k), l, cr.w * (0.4 + 0.6 * k))
			cr.part.CFrame = pose * cr.root * CFrame.new(0, l / 2 - 0.1, 0)
			cr.part.Transparency = k > 0 and 0.2 or 1
		end

		for _, ck in ipairs(cracks) do
			local k = math.clamp((crack - ck.at) / 0.12, 0, 1)
			if k > 0 then
				local sg = ck.seg
				local d = sg.to - sg.from
				local len = d.Magnitude * k
				local dir = d.Unit
				local c = sg.from + dir * (len / 2)
				local side = dir:Cross(sg.n)
				ck.part.Size = Vector3.new(len, 0.03, 0.08)
				ck.part.CFrame = pose * CFrame.fromMatrix(c, dir, sg.n, side)
				ck.part.Transparency = 0.1
			end
		end

		for _, p in ipairs(placed) do p[1].CFrame = pose * p[2] end

		for _, hl in ipairs(tints) do
			hl.FillTransparency = 1 - 0.5 * g
			hl.OutlineTransparency = 1 - 0.55 * g
		end
	end)

	-- when the scooter goes (the ride ended, or a revive brought a new one), so does
	-- everything this machine added; anyone still riding it is shown again, moving again
	local conn
	conn = scooter.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		conn:Disconnect()
		finish()
		Kit.unhide(hidden)
		startAnims(anims)
		cleanup()
	end)
	-- the shatter's pieces clean themselves up (Debris); the rest goes a little after it
	task.delay(math.max(start + T.END + 2 - workspace:GetServerTimeNow(), 0), function()
		startAnims(anims)
		for _, inst in ipairs(pieces) do
			if inst.Parent then inst:Destroy() end
		end
	end)
end

return Freeze
