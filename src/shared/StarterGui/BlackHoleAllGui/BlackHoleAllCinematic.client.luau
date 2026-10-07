--=====================================================================
-- BlackHoleAllCinematic   (StarterGui.BlackHoleAllGui)
--
-- BLACK HOLE - KILL ALL as THIS player sees it - every player in the server gets it, on the same
-- clock (Remotes.BlackHoleAllAlert { By, Start }: ScooterSystem.BlackHoleAll; every time, shot and
-- size is in ReplicatedStorage.TrollFx.BlackHoleAllTimeline). A disaster-movie cutscene:
--   the whole map    a slow push in; a deep rumble, the world darkening to violet, a purple tear
--                    opening high in the sky; GRAVITATIONAL ANOMALY DETECTED / <buyer> summoned
--                    the BLACK HOLE!
--   the black hole   (a cut through black) close up as it forms: a pitch-black core with a
--                    glowing rim, a shimmering halo bent round it, a disc of light spinning up
--                    round it, sparks and wisps spiralling in; a low hum
--   the pull         the wide shot, the map below: chunks of it torn up and spiralling in, jets
--                    of light out of its poles, the camera dragged towards it, the view
--                    stretching, the hum rising
--   the implosion    it caves in, spinning faster and faster, a ring of light rushing in; dead
--                    silence; then a flash, a burst of light and a ring racing out over the map
--   the end          a fade to black; everything comes back, and the game carries on
--                    (the rides' death popups, the lobby's respawn: ScooterSystem.NukeAll)
-- While it plays every other screen of the player's is put away and every control and menu
-- locked (FinishCutscene.Lock, as NUKE ALL and the trolls do); all of it comes back at the end.
-- EVERYTHING here is this machine's own picture: the map itself is never touched. (Not the
-- troll menu's BLACK HOLE, which swallows one duo: StarterPlayerScripts.TrollFx.BlackHole.)
--=====================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local Debris       = game:GetService("Debris")
local RS           = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui       = script.Parent

local fx       = RS:WaitForChild("TrollFx")
local T        = require(fx:WaitForChild("BlackHoleAllTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local soundsOf = fx:WaitForChild("BlackHoleAllSounds")
local Remotes  = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local cutscene = player:WaitForChild("PlayerScripts"):WaitForChild("FinishCutscene")
local Lock     = require(cutscene:WaitForChild("Lock"))
local HIDE_CORE = require(cutscene:WaitForChild("Config")).HideCoreGui
local seq, cseq = Kit.seq, Kit.cseq

local CAM_STEP   = "BlackHoleAllCinematic"
local CAM_PRI    = Enum.RenderPriority.Last.Value + 100   -- over every other camera in the game
local FONT       = Font.new("rbxasset://fonts/families/FredokaOne.json")
local VOID       = Color3.fromRGB(10, 0, 22)
local PURPLE     = Color3.fromRGB(165, 85, 255)
local LILAC      = Color3.fromRGB(225, 195, 255)
local HOT        = Color3.fromRGB(255, 245, 255)
local YELLOW     = Color3.fromRGB(255, 221, 0)
local LETTERBOX_MAX = 0.075   -- the black bars, top and bottom: at most this share of the screen's height each
local CINEMA = 2              -- the bars only crop the screen to a CINEMA : 1 frame (as the finish cutscene's
                              -- FinishCutscene.Fade): wide phones get none, 16:9 screens slim ones
local LETTERBOX = LETTERBOX_MAX   -- this screen's, worked out as each cinematic starts (fitBars)
local RETURN_FADE = 0.5    -- black -> the game, once everything is back
local UP        = CFrame.Angles(0, 0, math.rad(90))   -- a cylinder's length turned from X to Y
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SEGMENTS  = 16      -- curved beams making each ring of the disc
local KAPPA     = 4 / 3 * math.tan(math.pi / (2 * SEGMENTS))   -- how far each beam bows, x the radius, to make a circle
-- the disc's rings, inside out (their sizes are the timeline's T.RINGS): hot white at the
-- middle, through violet, to a dim indigo at the edge
-- (each arc fades from Alpha[1] to Alpha[2], every other one fainter: streaks that show it turning)
local RING_LOOK = {
	{ Colors = { HOT, Color3.fromRGB(230, 190, 255) },                           Alpha = { 0, 0.25 },    Glow = 0.35 },
	{ Colors = { Color3.fromRGB(215, 135, 255), Color3.fromRGB(170, 90, 255) },  Alpha = { 0.05, 0.35 }, Glow = 0.25 },
	{ Colors = { Color3.fromRGB(140, 85, 250), Color3.fromRGB(95, 60, 220) },    Alpha = { 0.12, 0.45 }, Glow = 0.15 },
	{ Colors = { Color3.fromRGB(70, 40, 165), Color3.fromRGB(40, 20, 110) },     Alpha = { 0.3, 0.6 },   Glow = 0 },
}
-- the chunks torn up off the map: grass, earth, stone
local CHUNK_COLORS = {
	Color3.fromRGB(95, 160, 70), Color3.fromRGB(120, 95, 70), Color3.fromRGB(130, 130, 135),
	Color3.fromRGB(80, 130, 60), Color3.fromRGB(160, 140, 110),
}

---------------------------------------------------------------- session
-- Everything taken registers how to give it back; given back once, in reverse (the same
-- contract as FinishCutscene's Lock, TrolledUI and NukeCinematic).
local Session = {}
Session.__index = Session
function Session.new() return setmetatable({ tasks = {}, alive = true }, Session) end
function Session:Add(name, fn) table.insert(self.tasks, { name = name, fn = fn }) end
function Session:Finish()
	if not self.alive then return end
	self.alive = false
	for i = #self.tasks, 1, -1 do
		local ok, err = pcall(self.tasks[i].fn)
		if not ok then warn("[BlackHoleAll] putting back '" .. self.tasks[i].name .. "' failed: " .. tostring(err)) end
	end
end

---------------------------------------------------------------- the screen
local function frame(name, props, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent or gui
	return f
end
local function label(name, props, strokeColor, strokeThickness, parent)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextScaled = true
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent or gui
	local s = Instance.new("UIStroke")
	s.Color = strokeColor
	s.Thickness = strokeThickness
	s.Parent = l
	return l, s
end

local top    = frame("BarTop", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, LETTERBOX), Position = UDim2.fromScale(0, -LETTERBOX), ZIndex = 2 })
local bottom = frame("BarBottom", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, LETTERBOX), Position = UDim2.fromScale(0, 1), ZIndex = 2 })
local edgeGlow = frame("EdgeGlow", { BackgroundColor3 = Color3.fromRGB(60, 10, 120), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 })
do
	local g = Instance.new("UIGradient")   -- violet at the edges, clear in the middle
	g.Transparency = seq({ { 0, 0 }, { 0.25, 0.85 }, { 0.75, 0.85 }, { 1, 0 } })
	g.Parent = edgeGlow
end
local warning = label("Warning", {
	Text = "\u{26A0} GRAVITATIONAL ANOMALY DETECTED \u{26A0}", TextColor3 = Color3.fromRGB(205, 150, 255), Visible = false, ZIndex = 5,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, LETTERBOX + 0.03), Size = UDim2.fromScale(0.8, 0.075),
}, Color3.new(0, 0, 0), 3)
local byLine = label("By", {
	Text = "", TextColor3 = YELLOW, Visible = false, ZIndex = 5,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, LETTERBOX + 0.11), Size = UDim2.fromScale(0.6, 0.05),
}, Color3.new(0, 0, 0), 1.5)
-- the bars (and the words just under the top one) fitted to this screen's shape
local function fitBars()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	LETTERBOX = (vp and vp.X > 0 and vp.Y > 0) and math.clamp((1 - (vp.X / vp.Y) / CINEMA) / 2, 0, LETTERBOX_MAX) or LETTERBOX_MAX
	top.Size, bottom.Size = UDim2.fromScale(1, LETTERBOX), UDim2.fromScale(1, LETTERBOX)
	top.Position, bottom.Position = UDim2.fromScale(0, -LETTERBOX), UDim2.fromScale(0, 1)
	warning.Position = UDim2.fromScale(0.5, LETTERBOX + 0.03)
	byLine.Position = UDim2.fromScale(0.5, LETTERBOX + 0.11)
end
local white = frame("Flash", { BackgroundColor3 = Color3.fromRGB(245, 235, 255), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
local black = frame("Black", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
for _, c in ipairs(gui:GetChildren()) do if c:IsA("GuiObject") then c.Visible = c.Name ~= "Warning" and c.Name ~= "By" end end

---------------------------------------------------------------- the pieces
local function piece(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

-- one glowing ring of the disc: SEGMENTS curved beams round the hub, lying flat in its plane
-- (FaceCamera off: each beam's width runs along its attachments' Y, which points out from the
-- middle, so the arcs join seamlessly). set(radius, width[, alpha]) sizes it; 0 hides it.
local function ring(hub, look, z)
	local r = { atts = {}, beams = {} }
	for i = 1, SEGMENTS do
		local a = Instance.new("Attachment")
		a.Parent = hub
		r.atts[i] = a
	end
	for i = 1, SEGMENTS do
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = r.atts[i], r.atts[i % SEGMENTS + 1]
		b.Color = ColorSequence.new(look.Colors[1], look.Colors[2])
		local a0, a1 = look.Alpha[1], look.Alpha[2]
		if i % 2 == 0 then a0 = (a0 + a1) / 2 end
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, a0), NumberSequenceKeypoint.new(1, a1) })
		b.LightEmission, b.LightInfluence = look.Glow, 0
		b.FaceCamera = false
		b.Segments = 6
		b.ZOffset = z
		b.Enabled = false
		b.Parent = hub
		r.beams[i] = b
	end
	function r.set(radius, width, alpha)
		local on = radius > 0.5 and width > 0.1
		for i = 1, SEGMENTS do
			local b = r.beams[i]
			b.Enabled = on
			if on then
				local th = (i - 1) / SEGMENTS * math.pi * 2
				local pos = Vector3.new(math.cos(th) * radius, 0, math.sin(th) * radius)
				local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
				r.atts[i].CFrame = CFrame.fromMatrix(pos, tangent, Vector3.new(math.cos(th), 0, math.sin(th)))
				b.CurveSize0, b.CurveSize1 = KAPPA * radius, KAPPA * radius
				b.Width0, b.Width1 = width, width
				if alpha then b.Transparency = NumberSequence.new(alpha) end
			end
		end
	end
	return r
end

-- The black hole: its core, rim, halo, the disc, the jets and the chunks it pulls in.
-- draw(t, dt) puts all of it where the clock says.
local function buildHole(home)
	local h = { angle = 0 }
	-- the core: pitch black (black neon gives back no light), its rim glowing round its edge
	h.core = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.new(0, 0, 0), Size = Vector3.one, Transparency = 1 }, home)
	h.rim = Instance.new("Highlight")
	h.rim.Adornee = h.core
	h.rim.FillTransparency = 1
	h.rim.OutlineColor = LILAC
	h.rim.OutlineTransparency = 1
	h.rim.DepthMode = Enum.HighlightDepthMode.Occluded
	h.rim.Parent = home
	-- the light bent round it: a shimmering halo, and a faint violet glow far out round it
	h.halo = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = PURPLE, Size = Vector3.one, Transparency = 1 }, home)
	h.aura = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(75, 25, 150), Size = Vector3.one, Transparency = 1 }, home)
	-- the disc: rings of light round a hub that turns
	h.hub = piece({ Transparency = 1, Size = Vector3.one }, home)
	h.rings = {}
	for i, look in ipairs(RING_LOOK) do h.rings[i] = ring(h.hub, look, #RING_LOOK - i) end
	h.inrush = ring(h.hub, { Colors = { HOT, LILAC }, Alpha = { 0.2, 0.2 }, Glow = 0.5 }, 6)   -- the ring rushing in as it collapses
	-- sparks and wisps streaming in from the disc's edge; they turn with it, so they spiral in
	local inward = {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, LockedToPart = true, Rate = 0,
	}
	local function with(props)
		for k, v in pairs(inward) do props[k] = v end
		return props
	end
	h.sparks = emitter(h.hub, with({
		Texture = SPARK_TEX, Color = cseq(HOT, PURPLE), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 9 }, { 1, 2 } }), Transparency = seq({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.6, 2.2),
	}))
	h.wisps = emitter(h.hub, with({
		Texture = SMOKE_TEX, Color = cseq(Color3.fromRGB(150, 80, 255), VOID), LightEmission = 0.5, LightInfluence = 0,
		Size = seq({ { 0, 50 }, { 1, 14 } }), Transparency = seq({ { 0, 0.5 }, { 0.7, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2, 2.6), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
	}))
	-- the jets out of its poles: a violet beam of light, a white-hot one inside it
	h.jets = {}
	for _, sign in ipairs({ 1, -1 }) do
		table.insert(h.jets, {
			sign = sign,
			outer = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PURPLE, Size = Vector3.one, Transparency = 1 }, home),
			inner = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = HOT, Size = Vector3.one, Transparency = 1 }, home),
		})
	end

	-- the chunks torn up off the map (made once the pull starts)
	function h.makeDebris()
		h.debris = {}
		for i = 1, T.DEBRIS do
			local s = T.DebrisSize(i)
			local p = piece({
				Material = (i % 3 == 0) and Enum.Material.Slate or Enum.Material.Grass,
				Color = CHUNK_COLORS[i % #CHUNK_COLORS + 1], Size = Vector3.new(s, s * 0.7, s * 0.85), Transparency = 1,
			}, home)
			local trail
			if i % 2 == 0 then
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.Position, a1.Position = Vector3.new(0, s * 0.3, 0), Vector3.new(0, -s * 0.3, 0)
				a0.Parent, a1.Parent = p, p
				trail = Instance.new("Trail")
				trail.Attachment0, trail.Attachment1 = a0, a1
				trail.Color = cseq(PURPLE, VOID)
				trail.Transparency = seq({ { 0, 0.3 }, { 1, 1 } })
				trail.LightEmission = 0.8
				trail.Lifetime = 0.45
				trail.FaceCamera = true
				trail.Enabled = false
				trail.Parent = p
			end
			h.debris[i] = { part = p, size = p.Size, trail = trail }
		end
	end

	function h.draw(t, dt)
		local core, disc = T.Grow(t)
		local R = T.CORE * core
		local D = T.CORE * disc
		h.angle += T.SpinSpeed(t) * dt
		local c = T.Collapse(t)

		-- the core, its rim, its halo
		if R > 0.2 then
			h.core.Transparency = 0
			h.core.Size = Vector3.one * R * 2
			h.core.CFrame = CFrame.new(T.CENTER)
			h.rim.OutlineTransparency = 0.05
			h.rim.OutlineColor = LILAC:Lerp(HOT, c)
			h.halo.Transparency = 0.1
			h.halo.Size = Vector3.one * R * 2 * T.HALO
			h.halo.CFrame = CFrame.new(T.CENTER) * CFrame.Angles(0, t * 0.6, 0)
			h.aura.Transparency = 0.93 + 0.02 * math.sin(t * 3)
			h.aura.Size = Vector3.one * R * 7
			h.aura.CFrame = CFrame.new(T.CENTER)
		else
			h.core.Transparency, h.halo.Transparency, h.aura.Transparency = 1, 1, 1
			h.rim.OutlineTransparency = 1
		end

		-- the disc, turning (faster and faster as it caves in)
		local rOut = T.RINGS[#T.RINGS].R * D
		h.hub.CFrame = T.DISC * CFrame.Angles(0, h.angle, 0)
		h.hub.Size = Vector3.new(math.max(rOut * 2, 1), 4, math.max(rOut * 2, 1))
		for i, rg in ipairs(h.rings) do
			local spec = T.RINGS[i]
			rg.set(spec.R * D, spec.W * disc)
		end
		-- feeding: sparks and wisps spiralling in (a trickle as it forms, a flood in the pull)
		local feed = (disc > 0.05 and t < T.COLLAPSE) and (t < T.PULL_AT and 0.35 or 1) or 0
		h.sparks.Rate = 160 * feed
		h.wisps.Rate = 26 * feed
		if rOut > 1 then
			h.sparks.Speed = NumberRange.new(rOut / 2.1, rOut / 1.7)
			h.wisps.Speed = NumberRange.new(rOut / 2.5, rOut / 2.1)
		end
		-- the collapse: a ring of light rushing in from far out
		if c > 0 and c < 1 then
			h.inrush.set(T.INRUSH * (1 - c) ^ 1.5, 60 + 70 * c, 0.6 - 0.45 * c)
		else
			h.inrush.set(0, 0)
		end

		-- the jets
		local j = T.Jets(t)
		for _, jet in ipairs(h.jets) do
			if j > 0.01 then
				local len = T.JET * j
				local flick = 1 + 0.12 * math.sin(t * 37 + jet.sign)
				local cf = T.DISC * CFrame.new(0, jet.sign * (R + len / 2), 0) * UP
				jet.outer.Size = Vector3.new(len, 46 * flick * j, 46 * flick * j)
				jet.outer.CFrame = cf
				jet.outer.Transparency = 0.4
				jet.inner.Size = Vector3.new(len, 18 * j, 18 * j)
				jet.inner.CFrame = cf
				jet.inner.Transparency = 0.15
			else
				jet.outer.Transparency, jet.inner.Transparency = 1, 1
			end
		end

		-- the chunks of the map, spiralling in
		if h.debris then
			for i, d in ipairs(h.debris) do
				local pos, k, rot = T.Debris(i, t)
				if pos and k > 0.02 then
					d.part.Transparency = 0
					d.part.Size = d.size * k
					d.part.CFrame = CFrame.new(pos) * rot
					if d.trail then d.trail.Enabled = true end
				else
					d.part.Transparency = 1
					if d.trail then d.trail.Enabled = false end
				end
			end
		end
	end
	return h
end

-- The implosion's burst, built the moment it caves in; draw(s) places it s seconds after
local function buildBurst(home)
	local b = {}
	b.ball  = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = HOT, Size = Vector3.one }, home)
	-- the shockwaves: thin rings of light flat in the disc's plane, racing out over the map
	local hub = piece({ Transparency = 1, Size = Vector3.one, CFrame = T.DISC }, home)
	b.wave  = ring(hub, { Colors = { HOT, LILAC }, Alpha = { 0.05, 0.3 }, Glow = 0.6 }, 7)
	b.wave2 = ring(hub, { Colors = { LILAC, PURPLE }, Alpha = { 0.3, 0.6 }, Glow = 0.3 }, 6)
	b.after = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = PURPLE, Size = Vector3.one, Transparency = 1 }, home)
	local point = piece({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(T.CENTER) }, home)
	Kit.burst(point, 160, {
		Texture = SPARK_TEX, Color = cseq(HOT, PURPLE), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 12 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.5, 2.6), Speed = NumberRange.new(220, 420), Drag = 1.2,
	})
	Kit.burst(point, 40, {
		Texture = SMOKE_TEX, Color = cseq(Color3.fromRGB(190, 140, 255), VOID), LightEmission = 0.4,
		Size = seq({ { 0, 60 }, { 1, 170 } }), Transparency = seq({ { 0, 0.3 }, { 0.8, 0.7 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2.5, 4), Speed = NumberRange.new(90, 170), Drag = 2.5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
	})
	-- motes of light drifting where it was
	local motes = emitter(point, {
		Texture = SPARK_TEX, Color = cseq(LILAC, PURPLE), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 7 }, { 1, 0 } }), Lifetime = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(15, 45),
		SpreadAngle = Vector2.new(180, 180), Rate = 30,
	})
	task.delay(3, function() motes.Rate = 0 end)

	function b.draw(s)
		-- the white-hot burst of light: a quick swell, cooling to violet as it fades
		local k = T.Clamp01(s / 0.35)
		b.ball.Size = Vector3.one * math.max(T.BURST * 2 * (1 - (1 - k) ^ 3), 1)
		b.ball.CFrame = CFrame.new(T.CENTER)
		b.ball.Color = HOT:Lerp(PURPLE, T.Clamp01(s / 0.6))
		b.ball.Transparency = s < 0.15 and 0 or math.min(0.2 + (s - 0.15) / 0.8, 1)
		-- the shockwave racing out over the whole map, and a slower violet one behind it
		local w = T.Clamp01(s / 2.4)
		if w < 1 then b.wave.set(T.RING_OUT * w ^ 0.6, 20 + 90 * (1 - w), 0.1 + 0.9 * w) else b.wave.set(0, 0) end
		local d = T.Clamp01(s / 3.6)
		if d < 1 then b.wave2.set(T.RING_OUT * 0.8 * d ^ 0.55, 30 + 140 * (1 - d), 0.35 + 0.65 * d) else b.wave2.set(0, 0) end
		-- a violet afterglow where it was, fading
		b.after.Size = Vector3.one * (160 + 60 * T.Clamp01(s / 4))
		b.after.CFrame = CFrame.new(T.CENTER)
		b.after.Transparency = s < 0.3 and 1 or math.min(0.55 + 0.45 * T.Clamp01((s - 0.3) / 3.5), 1)
	end
	return b
end

---------------------------------------------------------------- the cinematic
local playing = false
local current   -- the session of the cinematic playing, if any

local function play(info)
	local start = info.Start
	local function clock() return workspace:GetServerTimeNow() - start end
	if clock() > T.IMPLODE - 1 then return end   -- only just joined: too late to follow it
	playing = true
	local s = Session.new()
	current = s

	-- the whole map loaded in, as far as it can be
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, T.GROUND_ZERO, 3)
		pcall(player.RequestStreamAroundAsync, player, T.EST_LOOK, 3)
	end)

	-- every other screen away, every control and menu locked (as the trolls do)
	Lock.Controls(s)
	Lock.Hud(s, playerGui, gui, HIDE_CORE)

	-- the camera
	local cam = workspace.CurrentCamera
	local savedFov = cam.FieldOfView
	s:Add("camera", function()
		RunService:UnbindFromRenderStep(CAM_STEP)
		local c = workspace.CurrentCamera
		c.FieldOfView = savedFov
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then c.CameraSubject = hum end
		c.CameraType = Enum.CameraType.Custom
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			look = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
			c.CFrame = CFrame.lookAt(root.Position - look * 12 + Vector3.new(0, 4, 0), root.Position + Vector3.new(0, 1.5, 0))
		end
	end)

	-- the world's colour (this machine's own; gone at the end)
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "BlackHoleAllGrade"
	grade.Parent = Lighting
	s:Add("colour", function() grade:Destroy() end)

	-- this machine's pieces: the black hole, the burst
	local home = Instance.new("Folder")
	home.Name = "BlackHoleAllCinematic"
	home.Parent = Kit.mine()
	s:Add("pieces", function() home:Destroy() end)
	local hole = buildHole(home)
	local burst

	-- the sounds, heard as if right there (2D: they play on the screen)
	local sounds, volumes = {}, {}
	for _, snd in ipairs(soundsOf:GetChildren()) do
		if snd:IsA("Sound") then
			local c = snd:Clone()
			c.Parent = gui
			sounds[snd.Name] = c
			volumes[snd.Name] = snd.Volume
		end
	end
	s:Add("sounds", function()
		for _, c in pairs(sounds) do
			if c.IsPlaying and c.Looped then
				local tw = TweenService:Create(c, TweenInfo.new(0.4), { Volume = 0 })
				tw:Play()
				tw.Completed:Once(function() c:Destroy() end)
			else
				Debris:AddItem(c, 8)
			end
		end
	end)
	local function playSound(name, at)
		local c = sounds[name]
		if not c then return end
		c.Volume = volumes[name]
		c.TimePosition = at or 0
		c:Play()
	end
	local function fade(name, dur)
		local c = sounds[name]
		if c and c.IsPlaying then TweenService:Create(c, TweenInfo.new(dur), { Volume = 0 }):Play() end
	end

	-- the screen
	byLine.Text = ('%s summoned the <font color="#C9A2FF">BLACK HOLE!</font>'):format((tostring(info.By or "Someone"):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")))
	byLine.RichText = true
	warning.Visible, byLine.Visible = true, true
	fitBars()
	local barIn = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, barIn, { Position = UDim2.fromScale(0, 0) }):Play()
	TweenService:Create(bottom, barIn, { Position = UDim2.fromScale(0, 1 - LETTERBOX) }):Play()
	s:Add("screen", function()
		warning.Visible, byLine.Visible = false, false
		top.Position, bottom.Position = UDim2.fromScale(0, -LETTERBOX), UDim2.fromScale(0, 1)
		edgeGlow.BackgroundTransparency, white.BackgroundTransparency = 1, 1
	end)

	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	local function finish()
		if not s.alive then return end
		black.BackgroundTransparency = 0
		s:Finish()
		playing = false
		TweenService:Create(black, TweenInfo.new(RETURN_FADE), { BackgroundTransparency = 1 }):Play()
	end

	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAM_STEP, CAM_PRI, function(dt)
		local t = clock()
		if t >= T.END - 0.15 then finish() return end   -- a hair before the server's end: the popup takes it from there
		t = math.max(t, 0)
		local c = workspace.CurrentCamera
		c.CameraType = Enum.CameraType.Scriptable

		-- the camera, shaking (and tugged round, as if the black hole had hold of it)
		local cf, fov = T.Camera(t)
		local k = T.Shake(t)
		if k > 0 then
			local n = os.clock() * 22
			local big = t >= T.IMPLODE and 4 or 1.5
			cf = cf * CFrame.new(math.noise(n, 3.1) * k * big, math.noise(n, 8.7) * k * big, 0)
				* CFrame.Angles(math.noise(n, 1.9) * k * 0.02, math.noise(n, 6.6) * k * 0.02, math.noise(n, 5.3) * k * 0.04)
		end
		if t >= T.PULL_AT and t < T.IMPLODE then
			local tug = T.Clamp01((t - T.PULL_AT) / (T.COLLAPSE - T.PULL_AT))
			cf = cf * CFrame.Angles(0, 0, math.sin(t * 1.3) * 0.05 * tug + 0.12 * T.Collapse(t))
		end
		c.CFrame = cf
		c.FieldOfView = fov

		-- the sounds, on cue
		once("start", function() playSound("Rumble"); playSound("Bass") end)
		if t >= T.FORM_AT then
			once("open", function()
				playSound("Open")
				local hum = sounds.Hum
				if hum then
					hum.Volume = 0
					hum:Play()
					TweenService:Create(hum, TweenInfo.new(2.5), { Volume = volumes.Hum }):Play()
				end
			end)
		end
		if t >= T.EST_END - T.CUT then once("cut", function() playSound("Whoosh") end) end
		if t >= T.PULL_AT then
			once("pull", function() playSound("Whoosh"); playSound("Rumble"); playSound("Crackle") end)
		end
		if sounds.Hum and t < T.HUSH then
			sounds.Hum.PlaybackSpeed = 0.65 + 0.45 * T.Clamp01((t - T.PULL_AT) / (T.COLLAPSE - T.PULL_AT))   -- rising
		end
		if t >= T.COLLAPSE then once("collapse", function() playSound("Gulp"); playSound("Collapse") end) end
		if t >= T.HUSH then
			once("hush", function()
				fade("Hum", 0.15); fade("Bass", 0.15); fade("Rumble", 0.15); fade("Crackle", 0.15)
			end)
		end

		-- the black hole
		if t >= T.PULL_AT then once("debris", hole.makeDebris) end
		hole.draw(t, dt)

		-- THE IMPLOSION
		if t >= T.IMPLODE then
			once("boom", function()
				playSound("Boom"); playSound("BoomLayer")
				task.delay(1.2, function() if s.alive then playSound("Rumble") end end)
				burst = buildBurst(home)
			end)
			burst.draw(t - T.IMPLODE)
		end

		-- the world's colour: darkening to violet as it forms, then the flash, then lifting
		local dark = T.Dark(t)
		if t < T.IMPLODE then
			local pulse = 0.5 + 0.5 * math.sin(t * 3)
			grade.Brightness = -0.12 * dark
			grade.Contrast = 0.22 * dark
			grade.Saturation = -0.45 * dark
			grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(200, 175, 255), dark)
			edgeGlow.BackgroundTransparency = 1 - (0.25 + 0.25 * pulse) * dark
		else
			local a = t - T.IMPLODE
			grade.Brightness = 0.5 * (1 - T.Clamp01(a / 1.5)) - 0.12 * dark
			grade.Contrast = 0.22 * dark
			grade.Saturation = -0.45 * dark
			grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(200, 175, 255), dark)
			edgeGlow.BackgroundTransparency = 1 - 0.3 * dark
		end

		-- the words: the warning flashing
		warning.TextTransparency = (t < T.COLLAPSE and math.sin(t * 6) > -0.3) and 0 or 1
		warning.UIStroke.Transparency = warning.TextTransparency
		byLine.Visible = t < T.PULL_AT

		-- the flash and the blacks
		white.BackgroundTransparency = 1 - T.Flash(t)
		black.BackgroundTransparency = 1 - T.Black(t)
		-- the bars slide away just before the end
		if t >= T.END - T.END_FADE - 0.2 then
			once("bars", function()
				local out = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TweenService:Create(top, out, { Position = UDim2.fromScale(0, -LETTERBOX) }):Play()
				TweenService:Create(bottom, out, { Position = UDim2.fromScale(0, 1) }):Play()
			end)
		end
	end)

	-- never left in it
	task.delay(math.max(start + T.END + 4 - workspace:GetServerTimeNow(), 1), finish)
end

Remotes:WaitForChild("BlackHoleAllAlert").OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or type(info.Start) ~= "number" then return end
	-- the death popup has the camera (its frozen view and its buttons): this one sits it out
	if next(game:GetService("ContextActionService"):GetBoundActionInfo("DeathCameraNoControls")) ~= nil then return end
	-- a second one while this one plays waits its turn on the server; never two at once here
	if playing then return end
	local ok, err = pcall(play, info)
	if not ok then
		warn("[BlackHoleAll] " .. tostring(err))
		-- it broke part-way: everything it took (controls, screens, camera) comes back now
		if current and current.alive then current:Finish() end
		playing = false
	end
end)
