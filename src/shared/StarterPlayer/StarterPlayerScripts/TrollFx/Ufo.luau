--=====================================================================
-- Ufo   (TrollFx) - UFO ABDUCTION, as this machine shows it
--
-- On the scooter it was bought onto and nothing else: it stops dead, a cartoon flying saucer
-- swoops in (its lights chasing round the rim, a little alien in the dome) and hovers over it,
-- humming. Its tractor beam switches on - a glowing column round the scooter and both riders,
-- rings climbing it, sparkles floating up, a glow on the ground - and they float up it
-- together, turning slowly, tinted by it, into the saucer. Then they are gone, and it shoots
-- off into the sky. The riders stay welded as they ride (the scooter is only moved on this
-- screen). The clock is ReplicatedStorage.TrollFx.UfoTimeline (every timing, height and speed);
-- the sounds are ReplicatedStorage.TrollFx.UfoSounds; the shared pieces TrollFx.Kit.
--=====================================================================

local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local fx       = RS:WaitForChild("TrollFx")
local T        = require(fx:WaitForChild("UfoTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local soundsOf = fx:WaitForChild("UfoSounds")
local seq, cseq = Kit.seq, Kit.cseq

-- the look of it
local SAUCER_D  = 16                                  -- studs across
local BEAM_D    = 11                                  -- the beam's width (round the scooter and riders)
local HULL      = Color3.fromRGB(190, 198, 212)
local BEAM_COL  = Color3.fromRGB(120, 255, 180)
local DOME_COL  = Color3.fromRGB(150, 235, 255)
local ALIEN_COL = Color3.fromRGB(110, 225, 90)
local LIGHTS    = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 255, 150) }
local RIM_LIGHTS = 12
local RINGS     = 3                                   -- rings climbing the beam
local RING_TIME = 0.8                                 -- seconds for one to climb it

local Ufo = {}

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

-- a squashed ball (a SpecialMesh sphere `scale` studs across)
local function blob(scale, props)
	local p = piece(props)
	p.Size = Vector3.one
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = scale
	mesh.Parent = p
	return p
end

local UP = CFrame.Angles(0, 0, math.rad(90))   -- a cylinder standing up

function Ufo.Play(scooter)
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
	local models = { scooter, table.unpack(riders) }

	-- the ground under it (where the beam ends)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { home, table.unpack(models) }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(base.Position, Vector3.new(0, -12, 0), params)
	local groundY = hit and hit.Position.Y or base.Position.Y - 1.5

	---------------------------------------------------------------- the saucer
	local saucer = {}   -- { part, rel (from the UFO's CFrame), spins }
	local function add(p, rel, spins)
		own(p).Parent = home
		table.insert(saucer, { p, rel, spins })
		return p
	end
	local body = add(blob(Vector3.new(SAUCER_D, 3.2, SAUCER_D), { Name = "TrollUfo", Material = Enum.Material.Metal, Color = HULL, Reflectance = 0.25 }), CFrame.identity)
	add(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = Color3.fromRGB(120, 128, 145),
		Size = Vector3.new(0.5, SAUCER_D * 0.98, SAUCER_D * 0.98) }), UP)
	add(blob(Vector3.new(7, 5.5, 7), { Material = Enum.Material.Glass, Color = DOME_COL, Transparency = 0.45 }), CFrame.new(0, 1.3, 0))
	-- the little alien, looking out of the front
	add(blob(Vector3.new(2.2, 2.6, 2.2), { Material = Enum.Material.SmoothPlastic, Color = ALIEN_COL }), CFrame.new(0, 2.2, 0))
	for _, x in ipairs({ -0.45, 0.45 }) do
		add(blob(Vector3.new(0.55, 0.8, 0.3), { Material = Enum.Material.SmoothPlastic, Color = Color3.new(0, 0, 0) }),
			CFrame.new(x, 2.45, -1.0) * CFrame.Angles(0, 0, x > 0 and -0.3 or 0.3))
	end
	-- the glowing underside, where the beam comes from
	local belly = add(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = BEAM_COL,
		Size = Vector3.new(0.3, 6, 6) }), CFrame.new(0, -1.35, 0) * UP)
	-- lights chasing round the rim
	local rim = {}
	for i = 1, RIM_LIGHTS do
		local a = i / RIM_LIGHTS * math.pi * 2
		local l = add(piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = LIGHTS[1], Size = Vector3.one * 0.7 }),
			CFrame.new(math.cos(a) * SAUCER_D * 0.47, -0.2, math.sin(a) * SAUCER_D * 0.47), true)
		table.insert(rim, l)
	end
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Color = BEAM_COL
	spot.Angle = 50
	spot.Range = T.HEIGHT + 12
	spot.Brightness = 0
	spot.Parent = body

	---------------------------------------------------------------- the beam
	local outer = own(piece({ Name = "TrollBeam", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = BEAM_COL, Transparency = 1, Size = Vector3.one }))
	local inner = own(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(210, 255, 230), Transparency = 1, Size = Vector3.one }))
	local pool  = own(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = BEAM_COL, Transparency = 1, Size = Vector3.one }))
	outer.Parent, inner.Parent, pool.Parent = home, home, home
	local rings = {}
	for _ = 1, RINGS do
		local r = own(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(200, 255, 220), Transparency = 1, Size = Vector3.one }))
		r.Parent = home
		table.insert(rings, r)
	end
	-- sparkles floating up it, and its glow on the ground
	local floor = own(piece({ Name = "TrollBeamFloor", Transparency = 1, Size = Vector3.new(BEAM_D * 0.8, 0.2, BEAM_D * 0.8) }))
	floor.CFrame = CFrame.new(base.Position.X, groundY + 0.2, base.Position.Z)
	floor.Parent = home
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = cseq(Color3.fromRGB(230, 255, 240), BEAM_COL)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = seq({ { 0, 0.5 }, { 1, 0.1 } })
	motes.Transparency = seq({ { 0, 0.2 }, { 1, 1 } })
	motes.Lifetime = NumberRange.new(1.2, 1.8)
	motes.Speed = NumberRange.new(4, 8)
	motes.Acceleration = Vector3.new(0, 6, 0)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.SpreadAngle = Vector2.new(5, 5)
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.Rate = 0
	motes.Parent = floor
	local haze = Instance.new("ParticleEmitter")
	haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
	haze.Color = cseq(Color3.fromRGB(200, 255, 225), BEAM_COL)
	haze.LightEmission = 0.4
	haze.Size = seq({ { 0, 2 }, { 1, 5 } })
	haze.Transparency = seq({ { 0, 1 }, { 0.3, 0.8 }, { 1, 1 } })
	haze.Lifetime = NumberRange.new(1.5, 2.2)
	haze.Speed = NumberRange.new(1, 3)
	haze.Acceleration = Vector3.new(0, 3, 0)
	haze.Rotation = NumberRange.new(0, 360)
	haze.RotSpeed = NumberRange.new(-20, 20)
	haze.Shape = Enum.ParticleEmitterShape.Box
	haze.Rate = 0
	haze.Parent = floor
	local glow = Instance.new("PointLight")
	glow.Color = BEAM_COL
	glow.Range = 14
	glow.Brightness = 0
	glow.Parent = floor

	-- the scooter and both riders lit up by the beam
	local tints = {}
	for _, m in ipairs(models) do
		local h = own(Instance.new("Highlight"))
		h.Adornee = m
		h.FillColor = BEAM_COL
		h.OutlineColor = Color3.fromRGB(220, 255, 235)
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = home
		table.insert(tints, h)
	end

	-- its sounds, from the saucer
	local sounds = {}
	for _, s in ipairs(soundsOf:GetChildren()) do
		if s:IsA("Sound") then
			local c = s:Clone()
			c.Parent = body
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
	local step = "TrollUfo" .. shows
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

		once("hum", function() if sounds.Hover then sounds.Hover:Play() end end)

		-- the saucer: in, hovering, then away; its lights chasing round
		local ufo = T.Ufo(base, t)
		local spin = CFrame.Angles(0, t * 1.5, 0)
		for _, s in ipairs(saucer) do
			s[1].CFrame = s[3] and (ufo * spin * s[2]) or (ufo * s[2])
		end
		for i, l in ipairs(rim) do
			l.Color = LIGHTS[(i + math.floor(t * 8)) % #LIGHTS + 1]
		end

		-- the beam: from the saucer's belly down to the ground
		local on = T.BeamOn(t)
		local top = ufo.Position.Y - 1.4
		local len = math.max(top - groundY, 0.1)
		local mid = Vector3.new(ufo.Position.X, groundY + len / 2, ufo.Position.Z)
		local w = BEAM_D * (0.2 + 0.8 * on)
		outer.Size = Vector3.new(len, w, w)
		outer.CFrame = CFrame.new(mid) * UP
		outer.Transparency = 1 - 0.28 * on
		inner.Size = Vector3.new(len, w * 0.6, w * 0.6)
		inner.CFrame = outer.CFrame
		inner.Transparency = 1 - 0.3 * on
		pool.Size = Vector3.new(0.1, w * 1.1, w * 1.1)
		pool.CFrame = CFrame.new(mid.X, groundY + 0.06, mid.Z) * UP
		pool.Transparency = 1 - 0.55 * on
		for i, r in ipairs(rings) do
			local k = ((t - T.BEAM) / RING_TIME + (i - 1) / RINGS) % 1
			r.Size = Vector3.new(0.15, w * (1.02 - 0.25 * k), w * (1.02 - 0.25 * k))
			r.CFrame = CFrame.new(mid.X, groundY + len * k, mid.Z) * UP
			r.Transparency = 1 - 0.55 * on * math.sin(k * math.pi)
		end
		belly.Transparency = 0.6 - 0.6 * on
		spot.Brightness = 6 * on
		glow.Brightness = 3 * on
		motes.Rate = 40 * on
		haze.Rate = 10 * on
		for _, h in ipairs(tints) do
			h.FillTransparency = 1 - 0.45 * on
			h.OutlineTransparency = 1 - 0.6 * on
		end
		if t >= T.BEAM then
			once("beam", function() if sounds.Beam then sounds.Beam:Play() end end)
		end

		if t < T.EXPLODE then
			-- up the beam, turning slowly
			scooter:PivotTo(T.Pose(base, t) * pivotFromChassis)
			return
		end

		-- taken aboard: the scooter and its riders are gone, and it shoots off
		once("taken", function()
			scooter:PivotTo(base * pivotFromChassis)
			Kit.hide(scooter, hidden)
			for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
			if t < T.EXPLODE + 1 then
				local flash = Kit.ball(Color3.fromRGB(220, 255, 235), 2, ufo.Position - Vector3.new(0, 1.5, 0), 0.1)
				Kit.grow(flash, { Size = Vector3.one * 10, Transparency = 1 }, 0.35)
				if sounds.Away then sounds.Away:Play() end
			end
		end)
		if t >= T.EXPLODE + T.FLY then
			finish()
			if sounds.Hover then
				TweenService:Create(sounds.Hover, TweenInfo.new(0.4), { Volume = 0 }):Play()
			end
			for _, s in ipairs(saucer) do s[1].Transparency = 1 end
			for _, p in ipairs({ outer, inner, pool, table.unpack(rings) }) do p.Transparency = 1 end
			motes.Rate, haze.Rate, glow.Brightness = 0, 0, 0
		end
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

return Ufo
