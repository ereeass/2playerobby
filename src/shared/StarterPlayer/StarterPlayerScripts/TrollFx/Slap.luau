--=====================================================================
-- Slap   (TrollFx) - GIANT SLAP, as this machine shows it
--
-- On the scooter it was bought onto and nothing else: it stops dead; a rumble, and a huge
-- shadow grows on the ground beside them. A GIANT white cartoon glove on a black stick (the
-- troll's own picture, as parts with a black outline) swoops down out of the sky and stops
-- beside them. It just hangs there. An awkward pause, the camera creeping in, the hand
-- winding back, trembling... then SLAP: a sudden swing, SMACK!, a freeze-frame, a flash, a
-- ring and a dust cloud, stars - and the scooter and both riders are flung off tumbling into
-- the distance, spinning stars round their heads, until they vanish with a twinkle. The hand
-- follows through, recoils and goes back up out of sight. Nothing is really moved: the
-- scooter is only moved on this screen. The clock is ReplicatedStorage.TrollFx.SlapTimeline
-- (every timing, pose and speed); the sounds are ReplicatedStorage.TrollFx.SlapSounds; the
-- shared pieces TrollFx.Kit.
--=====================================================================

local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")

local fx       = RS:WaitForChild("TrollFx")
local T        = require(fx:WaitForChild("SlapTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local soundsOf = fx:WaitForChild("SlapSounds")
local seq, cseq = Kit.seq, Kit.cseq

-- the look of it
local HAND_SCALE = 1.05                              -- the glove's size (1: about twice a player)
local GLOVE      = Color3.fromRGB(238, 240, 248)
local STICK      = Color3.fromRGB(34, 36, 44)
local KNOB       = Color3.fromRGB(200, 204, 214)
local OUTLINE    = Color3.fromRGB(10, 10, 14)
local STAR       = Color3.fromRGB(255, 226, 60)
local STARS      = 5                                  -- cartoon stars spinning round them
local BOOM_UP    = 3.5                                -- where the SMACK lands, above the chassis

local Slap = {}

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
local function blob(scale, color)
	local p = piece({ Material = Enum.Material.SmoothPlastic, Color = color, Size = Vector3.one })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = scale
	mesh.Parent = p
	return p
end

-- The glove on its stick, as a model: { model, palm, parts = { {part, rel} } }. Its own space:
-- the palm's middle at the origin, the fingers up (+Y), the palm facing +X (towards them),
-- the thumb towards +Z. The stick goes off down and back from the wrist, as in the picture.
local function makeHand(parent)
	local S = HAND_SCALE
	local model = Instance.new("Model")
	model.Name = "TrollHand"
	local parts = {}
	local function add(p, rel)
		p.Parent = model
		table.insert(parts, { p, rel })
		return p
	end
	local palm = add(blob(Vector3.new(3.2, 7.4, 6.8) * S, GLOVE), CFrame.identity)
	palm.Name = "Palm"
	-- four chubby fingers, fanned a little, the middle one longest
	local fingers = { { z = -2.45, len = 5.4 }, { z = -0.82, len = 6.9 }, { z = 0.82, len = 6.6 }, { z = 2.45, len = 5.6 } }
	for _, f in ipairs(fingers) do
		local fan = f.z * 0.07
		add(blob(Vector3.new(2.3, f.len, 2.15) * S, GLOVE),
			CFrame.new(0, 2.9 * S, f.z * S) * CFrame.Angles(fan, 0, 0) * CFrame.new(0, f.len / 2 * S, 0))
	end
	-- the thumb, out to the side
	add(blob(Vector3.new(2.4, 5, 2.4) * S, GLOVE), CFrame.new(0.3 * S, -0.8 * S, 3.2 * S) * CFrame.Angles(-0.75, 0, 0) * CFrame.new(0, 2.2 * S, 0))
	-- the wrist
	add(blob(Vector3.new(2.8, 3.6, 4.4) * S, GLOVE), CFrame.new(-0.2 * S, -4.2 * S, 0))
	-- the stick, and its knob
	local len = 12 * S
	local dir = Vector3.new(-0.35, -0.9, -0.25).Unit   -- down and a little away
	local from = Vector3.new(-0.3 * S, -5.2 * S, 0)
	local stickAt = CFrame.lookAt(from + dir * len / 2, from + dir * len) * CFrame.Angles(0, math.rad(90), 0)
	add(piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = STICK,
		Size = Vector3.new(len, 0.9 * S, 0.9 * S) }), stickAt)
	add(piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Metal, Color = KNOB, Reflectance = 0.2,
		Size = Vector3.one * 1.3 * S }), CFrame.new(from + dir * len))
	-- the cartoon black outline round the whole thing
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = OUTLINE
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
	-- its motion blur: a pale smear left behind as it swings
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 9.5 * S, 0)
	a0.Parent = palm
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -4 * S, 0)
	a1.Parent = palm
	local blur = Instance.new("Trail")
	blur.Attachment0, blur.Attachment1 = a0, a1
	blur.Color = ColorSequence.new(Color3.new(1, 1, 1))
	blur.Transparency = seq({ { 0, 0.45 }, { 1, 1 } })
	blur.Lifetime = 0.14
	blur.LightInfluence = 0
	blur.FaceCamera = true
	blur.Enabled = false
	blur.Parent = palm
	model.Parent = parent
	return { model = model, palm = palm, parts = parts, blur = blur, outline = outline }
end

-- the big hit, at `pos` on the ground at `groundY`: a flash, a ring, dust, sparks, SMACK!
local function smack(pos, groundY, slapSound)
	local home = Kit.mine()
	local flash = Kit.ball(Color3.fromRGB(255, 255, 240), 2, pos, 0.05)
	Kit.grow(flash, { Size = Vector3.one * 14, Transparency = 1 }, 0.3)
	local ring = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 240, 170),
		Transparency = 0.15, Size = Vector3.new(0.3, 4, 4),
		CFrame = CFrame.new(pos.X, groundY + 0.25, pos.Z) * CFrame.Angles(0, 0, math.rad(90)) })
	ring.Parent = home
	Kit.grow(ring, { Size = Vector3.new(0.3, 42, 42), Transparency = 1 }, 0.5)
	Debris:AddItem(ring, 0.7)

	local point = piece({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	point.Parent = home
	Debris:AddItem(point, 3)
	-- a cartoon dust cloud, puffing out along the ground
	local dust = piece({ Transparency = 1, Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(pos.X, groundY + 0.3, pos.Z) })
	dust.Parent = home
	Debris:AddItem(dust, 3)
	Kit.burst(dust, 24, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = cseq(Color3.fromRGB(250, 246, 236), Color3.fromRGB(205, 196, 180)),
		Size = seq({ { 0, 3 }, { 1, 8 } }), Transparency = seq({ { 0, 0.1 }, { 0.7, 0.5 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(14, 26), Drag = 4,
		SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		LightInfluence = 0.6,
	})
	-- cartoon sparks and chunky stars flying out
	Kit.burst(point, 40, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = cseq(Color3.fromRGB(255, 255, 200), STAR),
		LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 1.2 }, { 1, 0.2 } }),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(35, 60), Drag = 3,
	})
	Kit.shout(point, "SMACK!", cseq(Color3.fromRGB(255, 244, 110), Color3.fromRGB(255, 110, 40)), Color3.fromRGB(80, 20, 10))
	if slapSound then
		local s = slapSound:Clone()
		s.Parent = point
		s:Play()
	end
end

-- the twinkle where they vanish into the distance
local function twinkle(pos, dingSound)
	local home = Kit.mine()
	local point = piece({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) })
	point.Parent = home
	Debris:AddItem(point, 4)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(90, 90)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Adornee = point
	board.Parent = point
	local star = Instance.new("TextLabel")
	star.BackgroundTransparency = 1
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.5, 0.5)
	star.Size = UDim2.fromScale(1, 1)
	star.Text = "\u{2605}"
	star.TextScaled = true
	star.TextColor3 = Color3.new(1, 1, 1)
	star.Parent = board
	local pop = Instance.new("UIScale")
	pop.Scale = 0.1
	pop.Parent = star
	local TweenService = game:GetService("TweenService")
	TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(star, TweenInfo.new(0.7, Enum.EasingStyle.Linear), { Rotation = 180 }):Play()
	task.delay(0.35, function()
		if not star.Parent then return end
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
	end)
	if dingSound then
		local s = dingSound:Clone()
		s.Parent = point
		s:Play()
	end
end

function Slap.Play(scooter)
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

	-- the ground beside them (where the shadow falls and the dust puffs)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { home, scooter, table.unpack(riders) }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(base.Position, Vector3.new(0, -12, 0), params)
	local groundY = hit and hit.Position.Y or base.Position.Y - 1.5

	-- the hand, its shadow, the stars and the fling's streak
	local hand = makeHand(home)
	own(hand.model)
	local shadow = own(piece({ Name = "TrollHandShadow", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic,
		Color = Color3.new(0, 0, 0), Transparency = 1, Size = Vector3.new(0.1, 1, 1) }))
	shadow.Parent = home
	local starHolder = own(piece({ Name = "TrollSlapStars", Transparency = 1, Size = Vector3.one * 0.2 }))
	starHolder.Parent = home
	local stars = {}
	for i = 1, STARS do
		local at = Instance.new("Attachment")
		at.Parent = starHolder
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromScale(1.8, 1.8)
		board.LightInfluence = 0
		board.Adornee = at
		board.Enabled = false
		board.Parent = starHolder
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Text = "\u{2605}"
		l.TextScaled = true
		l.TextColor3 = STAR
		l.Parent = board
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(120, 70, 0)
		edge.Thickness = 2
		edge.Parent = l
		table.insert(stars, { at = at, board = board, label = l, phase = (i - 1) / STARS * math.pi * 2 })
	end
	-- the streak behind them as they fly (on this screen only)
	local s0 = own(Instance.new("Attachment"))
	s0.Position = Vector3.new(0, -0.5, 0)
	s0.Parent = chassis
	local s1 = own(Instance.new("Attachment"))
	s1.Position = Vector3.new(0, 4.5, 0)
	s1.Parent = chassis
	local streak = own(Instance.new("Trail"))
	streak.Attachment0, streak.Attachment1 = s0, s1
	streak.Color = cseq(Color3.new(1, 1, 1), Color3.fromRGB(255, 230, 120))
	streak.Transparency = seq({ { 0, 0.35 }, { 1, 1 } })
	streak.Lifetime = 0.35
	streak.LightInfluence = 0
	streak.FaceCamera = true
	streak.Enabled = false
	streak.Parent = chassis

	-- its sounds, from where they stood
	local speaker = own(piece({ Name = "TrollSlapSpeaker", Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(base.Position) }))
	speaker.Parent = home
	local sounds = {}
	for _, s in ipairs(soundsOf:GetChildren()) do
		if s:IsA("Sound") then
			local c = s:Clone()
			c.Parent = speaker
			sounds[s.Name] = c
		end
	end
	local function play(name)
		local s = sounds[name]
		if s then s.TimePosition = 0; s:Play() end
	end

	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	shows += 1
	local step = "TrollSlap" .. shows
	local done = false
	local function finish()
		if done then return end
		done = true
		RunService:UnbindFromRenderStep(step)
	end
	local function placeHand(t)
		local pos, lean, shown, fast, turn = T.Hand(t)
		local cf = flat * CFrame.new(pos) * CFrame.Angles(0, 0, lean) * CFrame.Angles(0, turn, 0)
		for _, p in ipairs(hand.parts) do
			p[1].CFrame = cf * p[2]
			p[1].LocalTransparencyModifier = shown and 0 or 1
		end
		hand.blur.Enabled = shown and fast
		hand.outline.Enabled = shown
		-- its shadow on the ground: a dark blot that grows as it comes, sharper as it nears
		local world = cf.Position
		local height = math.max(world.Y - groundY, 0)
		local grow = t < T.ENTER and math.clamp(t / T.ENTER, 0, 1) or 1
		local d = (7 + 0.12 * height) * grow
		shadow.Size = Vector3.new(0.1, d, d * 0.8)
		shadow.CFrame = CFrame.new(world.X, groundY + 0.05, world.Z) * flat.Rotation * CFrame.Angles(0, 0, math.rad(90))
		shadow.Transparency = (shown or t < T.ENTER) and (1 - 0.5 * grow * (1 - math.min(height, 80) / 200)) or 1
	end

	-- every frame, before the cameras look at it
	RunService:BindToRenderStep(step, Enum.RenderPriority.Camera.Value - 1, function()
		if not (scooter.Parent and chassis.Parent) then finish() return end
		local t = clock()
		if t < 0 then return end

		once("rumble", function() play("Rumble") end)
		if t >= T.ENTER then once("enter", function() play("Whoosh") end) end
		if t >= T.SLAP then once("swing", function() play("Whoosh") end) end
		placeHand(t)

		if t >= T.IMPACT then
			once("smack", function()
				if t < T.IMPACT + 1 then
					smack((base * CFrame.new(0, BOOM_UP, 0)).Position, groundY, sounds.Slap)
				end
			end)
		end

		if t < T.EXPLODE then
			-- held still, then flung away tumbling
			local pose = T.Pose(base, t)
			scooter:PivotTo(pose * pivotFromChassis)
			streak.Enabled = t >= T.FLING
			-- stars spinning round their heads once they've been hit
			local dizzy = t >= T.IMPACT
			starHolder.CFrame = CFrame.new(pose.Position + Vector3.new(0, 6.5, 0))
			for _, s in ipairs(stars) do
				s.board.Enabled = dizzy
				local a = s.phase + t * 9
				s.at.Position = Vector3.new(math.cos(a) * 2.6, math.sin(a * 2) * 0.3, math.sin(a) * 2.6)
				s.label.Rotation = t * 400
			end
			return
		end

		-- off into the distance: a twinkle, and they are gone
		once("gone", function()
			local last = T.Pose(base, T.EXPLODE)
			scooter:PivotTo(base * pivotFromChassis)
			Kit.hide(scooter, hidden)
			for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
			streak.Enabled = false
			for _, s in ipairs(stars) do s.board.Enabled = false end
			if t < T.EXPLODE + 1 then twinkle(last.Position + Vector3.new(0, 2, 0), sounds.Ding) end
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

return Slap
