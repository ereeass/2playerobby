--=====================================================================
-- Kit   (ReplicatedStorage.TrollFx) - the pieces the troll shows share, on this machine only
--
-- Used by every show in StarterPlayerScripts.TrollFx (Rocket, Explode, Freeze). Nothing here is ever
-- sent anywhere: all of it is this machine's own picture.
--   Kit.mine()                     this machine's folder for its own pieces (TrollFxLocal)
--   Kit.ridersOf(scooter, chassis) the characters welded to that scooter
--   Kit.hide(model, rec) / Kit.unhide(rec)   hidden on this screen only, and back
--   Kit.colorsOf(scooter)          a few of its colours, for the flying bits
--   Kit.explode(pos, boomSound, colors)      the big cartoon explosion (ROCKET LAUNCH's)
--   Kit.shout(point, text, grad, edge)       its big popping words (BOOM!, CRACK!)
--   Kit.ball / Kit.grow / Kit.burst          its glowing balls, their tweens, particle bursts
--   Kit.seq / Kit.cseq             NumberSequence / ColorSequence shorthands
--=====================================================================

local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

local Kit = {}

local holder
local function mine()   -- this machine's own pieces (never sent anywhere)
	if holder and holder.Parent then return holder end
	holder = Instance.new("Folder")
	holder.Name = "TrollFxLocal"
	holder.Parent = workspace
	return holder
end

local function clamp01(x) return math.clamp(x, 0, 1) end

-- the characters riding this scooter: whatever is welded to its chassis that is not the scooter
local function ridersOf(scooter, chassis)
	local found, list = {}, {}
	for _, p in ipairs(chassis:GetConnectedParts(true)) do
		if not p:IsDescendantOf(scooter) then
			local m = p:FindFirstAncestorOfClass("Model")
			while m and not m:FindFirstChildOfClass("Humanoid") do m = m:FindFirstAncestorOfClass("Model") end
			if m and not found[m] then
				found[m] = true
				table.insert(list, m)
			end
		end
	end
	return list
end

-- hidden on this screen only (LocalTransparencyModifier never leaves this machine); `rec`
-- remembers how things were
local function hide(model, rec)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if rec[d] == nil then rec[d] = d.LocalTransparencyModifier end
			d.LocalTransparencyModifier = 1
		elseif (d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")) and d.Enabled then
			rec[d] = true
			d.Enabled = false
		elseif d:IsA("Humanoid") then
			if rec[d] == nil then rec[d] = d.DisplayDistanceType end
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

local function unhide(rec)
	for inst, was in pairs(rec) do
		if inst.Parent then
			if was == true then
				inst.Enabled = true
			elseif inst:IsA("Humanoid") then
				inst.DisplayDistanceType = was
			else
				inst.LocalTransparencyModifier = was
			end
		end
	end
	table.clear(rec)
end

---------------------------------------------------------------- the explosion
local function seq(points)
	local kp = {}
	for _, p in ipairs(points) do table.insert(kp, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(kp)
end
local function cseq(a, b) return ColorSequence.new(a, b) end

local function ball(color, size, pos, transparency)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.Size = Vector3.one * size
	p.CFrame = CFrame.new(pos)
	p.Parent = mine()
	Debris:AddItem(p, 1.2)
	return p
end

local function grow(p, props, dur)
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function burst(parent, count, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.SpreadAngle = Vector2.new(180, 180)
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	e:Emit(count)
	return e
end

-- big cartoon words popping up over `point` (a part) and fading: BOOM!, CRACK!, ...
-- `grad` its colour top to bottom (a ColorSequence), `edgeColor` its outline
local function shout(point, text, grad, edgeColor)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(15, 6.5)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Adornee = point
	board.Parent = point
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = FONT
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = board
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = grad
	g.Parent = label
	local edge = Instance.new("UIStroke")
	edge.Color = edgeColor
	edge.Thickness = 4
	edge.Parent = label
	local pop = Instance.new("UIScale")
	pop.Scale = 0.2
	pop.Parent = label
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.75, function()
		if not label.Parent then return end
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(edge, info, { Transparency = 1 }):Play()
		TweenService:Create(pop, info, { Scale = 1.25 }):Play()
	end)
end

-- a big cartoon explosion at `pos`: no force, nothing touched - a picture and a sound
local function explode(pos, boomSound, colors)
	local white = ball(Color3.fromRGB(255, 255, 236), 2, pos)
	grow(white, { Size = Vector3.one * 16, Transparency = 1 }, 0.35)
	local fire = ball(Color3.fromRGB(255, 140, 36), 3, pos, 0.05)
	grow(fire, { Size = Vector3.one * 24, Transparency = 1 }, 0.6)
	-- warm to the end: a red fading over a blue sky reads purple
	local glow = ball(Color3.fromRGB(255, 190, 70), 4, pos, 0.35)
	grow(glow, { Size = Vector3.one * 30, Transparency = 1 }, 0.7)

	-- a flat ring racing outwards
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery = true, false, false, false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 236, 150)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.3, 4, 4)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = mine()
	grow(ring, { Size = Vector3.new(0.3, 48, 48), Transparency = 1 }, 0.55)
	Debris:AddItem(ring, 0.8)

	-- smoke, sparks, fire puffs and cartoon stars, from one point
	local point = Instance.new("Part")
	point.Anchored, point.CanCollide, point.CanTouch, point.CanQuery = true, false, false, false
	point.Transparency = 1
	point.Size = Vector3.one * 0.2
	point.CFrame = CFrame.new(pos)
	point.Parent = mine()
	Debris:AddItem(point, 3.5)
	burst(point, 26, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = cseq(Color3.fromRGB(120, 116, 116), Color3.fromRGB(70, 68, 70)),
		Size = seq({ { 0, 4 }, { 1, 12 } }), Transparency = seq({ { 0, 0.15 }, { 0.7, 0.55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(10, 22), Drag = 3,
		Acceleration = Vector3.new(0, 4, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.5,
	})
	burst(point, 22, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = cseq(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 30)),
		LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 3 }, { 0.4, 6 }, { 1, 0 } }), Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(12, 24), Drag = 2,
	})
	burst(point, 70, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = cseq(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 120, 40)),
		LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 0.6 }, { 1, 0.1 } }),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(40, 70), Drag = 2.5,
		Acceleration = Vector3.new(0, -40, 0),
	})
	burst(point, 16, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = cseq(Color3.fromRGB(255, 250, 170), Color3.fromRGB(255, 214, 60)),
		LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 1.6 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.7, 1.0), Speed = NumberRange.new(18, 30), Drag = 3,
	})
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 190, 110)
	flash.Range = 45
	flash.Brightness = 10
	flash.Parent = point
	TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()

	-- bits of scooter flying out, tumbling (this machine's own, touching nothing)
	for _ = 1, 10 do
		local d = Instance.new("Part")
		d.Size = Vector3.new(0.4 + math.random() * 0.6, 0.25 + math.random() * 0.35, 0.4 + math.random() * 0.6)
		d.Color = colors[math.random(1, #colors)]
		d.Material = Enum.Material.SmoothPlastic
		d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
		d.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		d.Parent = mine()
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
		dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.yAxis
		d.AssemblyLinearVelocity = dir * (28 + math.random() * 24) + Vector3.new(0, 18, 0)
		d.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		Debris:AddItem(d, 2.2)
	end

	-- BOOM!
	shout(point, "BOOM!", cseq(Color3.fromRGB(255, 240, 90), Color3.fromRGB(255, 140, 30)), Color3.fromRGB(90, 22, 10))

	if boomSound then
		local s = boomSound:Clone()
		s.Parent = point
		s:Play()
	end
end

-- a few of the scooter's own colours (for the bits flying out of the explosion)
local function colorsOf(scooter)
	local colors = {}
	for _, p in ipairs(scooter:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.5 and #colors < 6 then table.insert(colors, p.Color) end
	end
	if #colors == 0 then colors = { Color3.fromRGB(230, 60, 60) } end
	return colors
end

Kit.mine     = mine
Kit.clamp01  = clamp01
Kit.ridersOf = ridersOf
Kit.hide     = hide
Kit.unhide   = unhide
Kit.seq      = seq
Kit.cseq     = cseq
Kit.explode  = explode
Kit.shout    = shout
Kit.ball     = ball
Kit.grow     = grow
Kit.burst    = burst
Kit.colorsOf = colorsOf

return Kit
