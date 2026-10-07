--=====================================================================
-- DragonCinematic   (StarterGui.DragonGui)
--
-- LAVA DRAGON as THIS player sees it - every player in the server gets it, on the same clock
-- (Remotes.DragonAlert { By, Start }: ScooterSystem.LavaDragon; every time, shot, position and
-- size is in ReplicatedStorage.TrollFx.DragonTimeline). A monster-movie cutscene:
--   the whole map     a slow push in over the obby; a roar echoes, the sea below glows red
--   the rise          (a cut through black) low over the sea: the lava pool boils, and the
--                     dragon bursts up out of it in a spray of lava, twisting into the sky
--   the roar          right in its face as it rears back and ROARS; the screen shakes
--   the flight        it dives and flies the whole course, the camera chasing it, breathing a
--                     river of fire that leaves the course burning behind it
--   the fireball      high over the map it charges a fireball in its jaws; silence; it spits it
--   the blast         a flash, a firestorm, lava bursting up all over the map, a shockwave,
--                     embers raining down; the dragon roars and flies off
--   the end           a fade to black; everything comes back, and the game carries on
--                     (the rides' death popups, the lobby's respawn: ScooterSystem.NukeAll)
-- While it plays every other screen of the player's is put away and every control and menu
-- locked (FinishCutscene.Lock, as NUKE ALL and the trolls do); all of it comes back at the end.
-- EVERYTHING here is this machine's own picture: the map itself is never touched.
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
local T        = require(fx:WaitForChild("DragonTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local template = fx:WaitForChild("LavaDragonModel")
local soundsOf = fx:WaitForChild("DragonSounds")
local Remotes  = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local cutscene = player:WaitForChild("PlayerScripts"):WaitForChild("FinishCutscene")
local Lock     = require(cutscene:WaitForChild("Lock"))
local HIDE_CORE = require(cutscene:WaitForChild("Config")).HideCoreGui
local seq, cseq = Kit.seq, Kit.cseq

local CAM_STEP    = "DragonCinematic"
local CAM_PRI     = Enum.RenderPriority.Last.Value + 100   -- over every other camera in the game
local FONT        = Font.new("rbxasset://fonts/families/FredokaOne.json")
local HOT         = Color3.fromRGB(255, 225, 120)
local LAVA        = Color3.fromRGB(255, 110, 20)
local DEEP        = Color3.fromRGB(200, 35, 8)
local YELLOW      = Color3.fromRGB(255, 221, 0)
local SMOKE       = Color3.fromRGB(70, 55, 50)
local LETTERBOX_MAX = 0.075   -- the black bars, top and bottom: at most this share of the screen's height each
local CINEMA = 2              -- the bars only crop the screen to a CINEMA : 1 frame (as the finish cutscene's
                              -- FinishCutscene.Fade): wide phones get none, 16:9 screens slim ones
local LETTERBOX = LETTERBOX_MAX   -- this screen's, worked out as each cinematic starts (fitBars)
local RETURN_FADE = 0.5     -- black -> the game, once everything is back
local MAX_FIRES   = 80      -- burning patches the breath leaves on the course
local FIRE_EVERY  = 0.06    -- seconds between them
local UP          = CFrame.Angles(0, 0, math.rad(90))   -- a cylinder standing up / lying flat
local FIRE_TEX    = "rbxasset://textures/particles/fire_main.dds"
local SPARK_TEX   = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX   = "rbxasset://textures/particles/smoke_main.dds"

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
		if not ok then warn("[Dragon] putting back '" .. self.tasks[i].name .. "' failed: " .. tostring(err)) end
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
local heatGlow = frame("HeatGlow", { BackgroundColor3 = LAVA, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 })
do
	local g = Instance.new("UIGradient")   -- glowing at the edges, clear in the middle
	g.Transparency = seq({ { 0, 0 }, { 0.25, 0.85 }, { 0.75, 0.85 }, { 1, 0 } })
	g.Parent = heatGlow
end
local warning = label("Warning", {
	Text = "\u{26A0} THE LAVA DRAGON HAS AWAKENED \u{26A0}", TextColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 5,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, LETTERBOX + 0.03), Size = UDim2.fromScale(0.85, 0.075),
}, Color3.fromRGB(35, 6, 0), 3)
do
	local g = Instance.new("UIGradient")   -- magma: yellow-hot at the top, deep red at the bottom
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 120)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 150, 30)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(240, 70, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 20, 5)),
	})
	g.Parent = warning
end
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
local white = frame("Flash", { BackgroundColor3 = Color3.fromRGB(255, 240, 210), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
local black = frame("Black", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9 })

---------------------------------------------------------------- pieces
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

-- The dragon, scaled up, taken apart into what moves together: its body, each wing (beating
-- round its shoulder), its tail (swaying round its base). place(t) puts it where the clock says.
local function buildDragon(home)
	local S = T.SCALE
	local d = template:Clone()
	d:PivotTo(CFrame.new(0, -3000, 0))
	d.Parent = home
	d:ScaleTo(S)
	-- its own lights and embers are for the podium; the cinematic makes its own
	for _, x in ipairs(d:GetDescendants()) do
		if x:IsA("Light") or x:IsA("ParticleEmitter") then x:Destroy() end
	end
	local pivot = d:GetPivot()
	local joints = {
		R = CFrame.new(template:GetAttribute("ShoulderR") * S),
		L = CFrame.new(template:GetAttribute("ShoulderL") * S),
		Tail = CFrame.new(template:GetAttribute("TailBase") * S),
	}
	local parts, offs, groups = {}, {}, {}
	for _, p in ipairs(d:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CastShadow = false
			local off = pivot:ToObjectSpace(p.CFrame)
			local group = "Body"
			if p:IsDescendantOf(d.Wings) then group = off.X > 0 and "R" or "L"
			elseif p:IsDescendantOf(d.Tail) then group = "Tail" end
			if joints[group] then off = joints[group]:Inverse() * off end
			table.insert(parts, p)
			table.insert(offs, off)
			table.insert(groups, group)
		end
	end
	local mouth = d.Head.MouthGlow
	local torso = d.Body.Torso
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = LAVA, 60, 3
	glow.Parent = torso
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(255, 120, 40)
	outline.OutlineTransparency = 0.45
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = d
	-- embers always drifting off it
	emitter(torso, {
		Texture = SPARK_TEX, Color = cseq(HOT, LAVA), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 3 }, { 1, 0 } }), Lifetime = NumberRange.new(1, 1.8), Rate = 40,
		Speed = NumberRange.new(5, 15), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 20, 0),
	})

	local cfs = table.create(#parts)
	local self = { model = d, mouth = mouth, torso = torso }
	function self.place(t)
		local base = T.Dragon(t)
		local flap = T.Flap(t)
		local at = {
			Body = base,
			R = base * joints.R * CFrame.Angles(0, 0, flap),
			L = base * joints.L * CFrame.Angles(0, 0, -flap),
			Tail = base * joints.Tail * CFrame.Angles(0.08 * math.sin(t * 2.2), 0.3 * math.sin(t * 2.8), 0),
		}
		for i, p in ipairs(parts) do cfs[i] = at[groups[i]] * offs[i] end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return base
	end
	return self
end

-- The lava pool on the sea it rises out of
local function buildPool(home)
	local b = {}
	b.rim = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = DEEP, Transparency = 0.2, Size = Vector3.one }, home)
	b.lava = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = LAVA, Size = Vector3.one }, home)
	b.crust = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.CrackedLava, Color = Color3.fromRGB(255, 120, 40), Size = Vector3.one }, home)
	b.bubbles = emitter(b.lava, {
		Texture = FIRE_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 14 }, { 1, 30 } }), Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(20, 60), Rate = 0,
		EmissionDirection = Enum.NormalId.Right, SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, -40, 0),
	})
	b.steam = emitter(b.rim, {
		Texture = SMOKE_TEX, Color = cseq(Color3.fromRGB(255, 140, 90), SMOKE),
		Size = seq({ { 0, 30 }, { 1, 90 } }), Transparency = seq({ { 0, 0.4 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(15, 40), Rate = 0, LightInfluence = 0.5,
		EmissionDirection = Enum.NormalId.Right, SpreadAngle = Vector2.new(30, 30), Rotation = NumberRange.new(0, 360),
	})
	b.light = Instance.new("PointLight")
	b.light.Color, b.light.Range, b.light.Brightness = LAVA, 60, 0
	b.light.Parent = b.lava
	function b.draw(t)
		local k = T.Pool(t)
		local r = math.max(T.POOL_R * (0.3 + 0.7 * k), 1)
		local wob = 1 + 0.03 * math.sin(t * 5)
		b.rim.Size = Vector3.new(1, r * 2.3 * wob, r * 2.3 * wob)
		b.rim.CFrame = CFrame.new(T.POOL) * UP
		b.lava.Size = Vector3.new(1.4, r * 2, r * 2)
		b.lava.CFrame = CFrame.new(T.POOL + Vector3.new(0, 0.3, 0)) * UP
		b.crust.Size = Vector3.new(1.6, r * 1.6, r * 1.6)
		b.crust.CFrame = CFrame.new(T.POOL + Vector3.new(0, 0.5, 0)) * UP * CFrame.Angles(t * 0.2, 0, 0)
		for _, p in ipairs({ b.rim, b.lava, b.crust }) do p.Transparency = k <= 0.01 and 1 or p == b.rim and 0.2 or 0 end
		b.bubbles.Rate = 60 * k
		b.steam.Rate = 12 * k
		b.light.Brightness = 6 * k
	end
	return b
end

-- Everything the blast is made of, built at the impact; draw(s) places it s seconds after
local function buildBlast(home)
	local gz = T.GROUND_ZERO
	local b = {}
	b.core = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 250, 220), Size = Vector3.one }, home)
	b.fire = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = LAVA, Size = Vector3.one }, home)
	b.heat = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 90, 30), Transparency = 1, Size = Vector3.one }, home)
	b.ring = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 200, 120), Size = Vector3.one }, home)
	b.ring2 = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = DEEP, Size = Vector3.one }, home)
	local point = piece({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(gz + Vector3.new(0, 20, 0)) }, home)
	Kit.burst(point, 70, {
		Texture = FIRE_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 40 }, { 0.5, 90 }, { 1, 0 } }), Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(120, 240), Drag = 2,
	})
	Kit.burst(point, 160, {
		Texture = SPARK_TEX, Color = cseq(HOT, LAVA), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 10 }, { 1, 2 } }),
		Lifetime = NumberRange.new(1.8, 3), Speed = NumberRange.new(180, 380), Drag = 1,
		Acceleration = Vector3.new(0, -120, 0),
	})
	Kit.burst(point, 40, {
		Texture = SMOKE_TEX, Color = cseq(Color3.fromRGB(120, 80, 60), SMOKE),
		Size = seq({ { 0, 60 }, { 1, 170 } }), Transparency = seq({ { 0, 0.2 }, { 0.8, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(80, 160), Drag = 2.5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), LightInfluence = 0.4,
	})
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = LAVA, 60, 20
	light.Parent = point
	TweenService:Create(light, TweenInfo.new(4), { Brightness = 2 }):Play()
	-- dark smoke rising off the middle
	emitter(point, {
		Texture = SMOKE_TEX, Color = cseq(Color3.fromRGB(150, 70, 40), SMOKE),
		Size = seq({ { 0, 50 }, { 1, 150 } }), Transparency = seq({ { 0, 0.3 }, { 0.7, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(40, 80), Rate = 14, LightInfluence = 0.4,
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25), Rotation = NumberRange.new(0, 360),
	})
	-- embers raining down over the whole map
	local sky = piece({ Transparency = 1, Size = Vector3.new(1400, 1, 1400), CFrame = CFrame.new(gz + Vector3.new(0, 420, 0)) }, home)
	emitter(sky, {
		Texture = SPARK_TEX, Color = cseq(HOT, LAVA), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 5 }, { 1, 2 } }), Lifetime = NumberRange.new(5, 7), Rate = 260,
		Speed = NumberRange.new(50, 90), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(15, 15),
	})
	-- lava bursting up all around the map (wherever the ground is under each spot)
	local rng = Random.new(31)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { home, Kit.mine() }
	b.geysers = {}
	for i = 1, T.GEYSERS do
		local a = (i / T.GEYSERS) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(T.GEYSER_R[1], T.GEYSER_R[2])
		local x, z = gz.X + math.cos(a) * r, gz.Z + math.sin(a) * r
		local hit = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -1600, 0), params)
		local base = Vector3.new(x, math.max(hit and hit.Position.Y or 0, T.SEA), z)   -- out of the sea where there's no ground
		local g = {
			base = base, delay = rng:NextNumber(0.05, 1.3), height = rng:NextNumber(140, 260), width = rng:NextNumber(24, 40),
			col = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = LAVA, Size = Vector3.one, Transparency = 1 }, home),
			blob = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = HOT, Size = Vector3.one, Transparency = 1 }, home),
		}
		g.spray = emitter(g.blob, {
			Texture = SPARK_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
			Size = seq({ { 0, 12 }, { 1, 4 } }), Lifetime = NumberRange.new(1.2, 2), Rate = 0,
			Speed = NumberRange.new(60, 130), SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, -160, 0),
			EmissionDirection = Enum.NormalId.Top,
		})
		table.insert(b.geysers, g)
	end

	function b.draw(s)
		-- the white-hot core, then the firestorm swelling and cooling to deep red
		local k = T.Clamp01(s / 0.4)
		b.core.Size = Vector3.one * (20 + 220 * k)
		b.core.CFrame = CFrame.new(gz)
		b.core.Transparency = k
		local f = T.Clamp01(s / 1.3)
		local r = T.FIREBALL * (1 - (1 - f) ^ 3)
		b.fire.Size = Vector3.one * math.max(r * 2, 1)
		b.fire.CFrame = CFrame.new(gz + Vector3.new(0, r * 0.25, 0))
		b.fire.Color = HOT:Lerp(LAVA, T.Clamp01(s / 0.8)):Lerp(DEEP, T.Clamp01((s - 0.8) / 2))
		b.fire.Transparency = s < 1.2 and 0.05 or math.min(0.05 + (s - 1.2) / 1.8, 1)
		-- the heat dome
		local h = T.Clamp01(s / 1.1)
		b.heat.Size = Vector3.one * math.max(T.HEAT * 2 * (1 - (1 - h) ^ 2), 1)
		b.heat.CFrame = CFrame.new(gz)
		b.heat.Transparency = s < 1.1 and 0.6 or math.min(0.6 + (s - 1.1) / 2.2 * 0.4, 1)
		-- the shockwave racing out over everything, a ring of fire behind it
		local w = T.Clamp01(s / 2.4)
		local wr = T.SHOCKWAVE * w ^ 0.6
		b.ring.Size = Vector3.new(3, math.max(wr * 2, 1), math.max(wr * 2, 1))
		b.ring.CFrame = CFrame.new(gz + Vector3.new(0, 3, 0)) * UP
		b.ring.Transparency = 0.1 + 0.9 * w
		local d = T.Clamp01(s / 3.4)
		local dr = T.SHOCKWAVE * 0.8 * d ^ 0.55
		b.ring2.Size = Vector3.new(10, math.max(dr * 2, 1), math.max(dr * 2, 1))
		b.ring2.CFrame = CFrame.new(gz + Vector3.new(0, 6, 0)) * UP
		b.ring2.Transparency = 0.35 + 0.65 * d
		-- the lava geysers: up, spraying, then sinking back down
		for _, g in ipairs(b.geysers) do
			local ls = s - g.delay
			local up = ls <= 0 and 0 or T.Smooth(ls / 0.45) * (1 - T.Smooth((ls - 2.6) / 1.3))
			local hgt = math.max(g.height * up, 0.1)
			local wob = 1 + 0.08 * math.sin(ls * 11)
			g.col.Size = Vector3.new(hgt, g.width * wob, g.width * wob)
			g.col.CFrame = CFrame.new(g.base + Vector3.new(0, hgt / 2, 0)) * UP
			g.col.Color = HOT:Lerp(LAVA, T.Clamp01(ls / 1.2))
			g.col.Transparency = up < 0.02 and 1 or 0
			g.blob.Size = Vector3.one * g.width * 1.6 * wob
			g.blob.CFrame = CFrame.new(g.base + Vector3.new(0, hgt, 0))
			g.blob.Transparency = up < 0.02 and 1 or 0
			g.spray.Rate = up > 0.3 and 45 or 0
		end
	end
	return b
end

-- a patch of the course set burning by the breath (this screen only)
local function burnAt(home, pos, normal)
	local n = normal.Magnitude > 0.1 and normal.Unit or Vector3.yAxis
	local side = math.abs(n.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local cf = CFrame.fromMatrix(pos + n * 0.6, n, n:Cross(side).Unit)
	local size = math.random(26, 40)
	local p = piece({
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = LAVA, Transparency = 0.25,
		Size = Vector3.new(0.6, size, size), CFrame = cf,
	}, home)
	emitter(p, {
		Texture = FIRE_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 14 }, { 0.5, 22 }, { 1, 0 } }), Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.7, 1.2), Rate = 14, Speed = NumberRange.new(14, 30),
		EmissionDirection = Enum.NormalId.Right, SpreadAngle = Vector2.new(15, 15),
	})
	Kit.burst(p, 10, {
		Texture = SPARK_TEX, Color = cseq(HOT, LAVA), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 6 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(40, 90),
		Acceleration = Vector3.new(0, -80, 0),
	})
	if math.random() < 0.35 then
		emitter(p, {
			Texture = SMOKE_TEX, Color = cseq(Color3.fromRGB(110, 70, 55), SMOKE),
			Size = seq({ { 0, 20 }, { 1, 60 } }), Transparency = seq({ { 0, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2, 3), Rate = 4, Speed = NumberRange.new(15, 30), LightInfluence = 0.5,
			EmissionDirection = Enum.NormalId.Right, Rotation = NumberRange.new(0, 360),
		})
	end
	return p
end

---------------------------------------------------------------- the cinematic
local playing = false
local current   -- the session of the cinematic playing, if any

local function play(info)
	local start = info.Start
	local function clock() return workspace:GetServerTimeNow() - start end
	if clock() > T.IMPACT - 1 then return end   -- only just joined: too late to follow it
	playing = true
	local s = Session.new()
	current = s

	-- the map loaded in along its flight, as far as it can be
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, T.GROUND_ZERO, 3)
		for _, p in ipairs(T.PATH) do pcall(player.RequestStreamAroundAsync, player, p, 2) end
	end)

	-- every other screen away, every control and menu locked (as NUKE ALL and the trolls do)
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

	-- the world's colour
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "DragonGrade"
	grade.Parent = Lighting
	s:Add("colour", function() grade:Destroy() end)

	-- this machine's pieces: the dragon, the pool, the breath, the fires, the fireball, the blast
	local home = Instance.new("Folder")
	home.Name = "DragonCinematic"
	home.Parent = Kit.mine()
	s:Add("pieces", function() home:Destroy() end)
	local dragon = buildDragon(home)
	local pool = buildPool(home)
	-- the breath: pouring out of its jaws, aimed down at the course ahead of it
	local breathAt = Instance.new("Attachment")
	breathAt.Parent = dragon.mouth
	local breath = emitter(breathAt, {
		Texture = FIRE_TEX, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HOT),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 150, 40)),
			ColorSequenceKeypoint.new(0.7, LAVA),
			ColorSequenceKeypoint.new(1, DEEP),
		}),
		LightEmission = 0.6, LightInfluence = 0, ZOffset = 2,
		Size = seq({ { 0, 14 }, { 0.4, 45 }, { 1, 80 } }), Transparency = seq({ { 0, 0.05 }, { 0.8, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.55, 0.8), Speed = NumberRange.new(420, 520), Drag = 1.2, Rate = 0,
		EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(7, 7),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
	})
	local breathCore = emitter(breathAt, {
		Texture = SPARK_TEX, Color = cseq(Color3.fromRGB(255, 255, 230), HOT), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 10 }, { 1, 24 } }), Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(500, 600), Rate = 0,
		EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(3, 3),
	})
	-- the jet itself: a glowing core and fire round it, widening from the jaws to where it lands
	local jet = {}
	for i = 1, 3 do
		jet[i] = {
			core = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = HOT, Transparency = 1, Size = Vector3.one }, home),
			fire = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = LAVA, Transparency = 1, Size = Vector3.one }, home),
		}
	end
	local splash = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = HOT, Transparency = 1, Size = Vector3.one }, home)
	local breathLight = Instance.new("PointLight")
	breathLight.Color, breathLight.Range, breathLight.Brightness = LAVA, 60, 0
	breathLight.Parent = dragon.mouth
	-- the fireball it spits
	local fireball = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = HOT, Size = Vector3.one, Transparency = 1 }, home)
	local ballFire = emitter(fireball, {
		Texture = FIRE_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 40 }, { 1, 10 } }), Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(10, 30), Rate = 0,
		SpreadAngle = Vector2.new(180, 180),
	})
	local ballLight = Instance.new("PointLight")
	ballLight.Color, ballLight.Range, ballLight.Brightness = LAVA, 60, 0
	ballLight.Parent = fireball
	local spitFrom = T.Dragon(T.SPIT) * (template:GetAttribute("Mouth") * T.SCALE)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { home, Kit.mine() }
	rayParams.IgnoreWater = true
	local fires, nextFire = 0, 0

	-- the sounds, heard as if right there (2D: they play on the screen)
	local sounds = {}
	for _, snd in ipairs(soundsOf:GetChildren()) do
		if snd:IsA("Sound") then
			local c = snd:Clone()
			c.Parent = gui
			sounds[snd.Name] = c
		end
	end
	if sounds.Lava then sounds.Lava.Looped = true end
	s:Add("sounds", function()
		for _, c in pairs(sounds) do
			if c.IsPlaying then
				local tw = TweenService:Create(c, TweenInfo.new(0.4), { Volume = 0 })
				tw:Play()
				tw.Completed:Once(function() c:Destroy() end)
			else
				Debris:AddItem(c, 8)
			end
		end
	end)
	local function sfx(name, at)
		local c = sounds[name]
		if not c then return end
		c.Volume = soundsOf[name].Volume
		c.TimePosition = at or 0
		c:Play()
	end
	local function fade(name, dur)
		local c = sounds[name]
		if c and c.IsPlaying then TweenService:Create(c, TweenInfo.new(dur), { Volume = 0 }):Play() end
	end

	-- the screen
	byLine.Text = ('%s unleashed the <font color="#FF8A1E">LAVA DRAGON!</font>'):format((tostring(info.By or "Someone"):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")))
	byLine.RichText = true
	warning.Visible, byLine.Visible = true, true
	fitBars()
	local barIn = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, barIn, { Position = UDim2.fromScale(0, 0) }):Play()
	TweenService:Create(bottom, barIn, { Position = UDim2.fromScale(0, 1 - LETTERBOX) }):Play()
	s:Add("screen", function()
		warning.Visible, byLine.Visible = false, false
		top.Position, bottom.Position = UDim2.fromScale(0, -LETTERBOX), UDim2.fromScale(0, 1)
		heatGlow.BackgroundTransparency, white.BackgroundTransparency = 1, 1
	end)

	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	local blast

	local function finish()
		if not s.alive then return end
		black.BackgroundTransparency = 0
		s:Finish()
		playing = false
		TweenService:Create(black, TweenInfo.new(RETURN_FADE), { BackgroundTransparency = 1 }):Play()
	end

	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAM_STEP, CAM_PRI, function()
		local t = clock()
		if t >= T.END - 0.15 then finish() return end   -- a hair before the server's end: the popup takes it from there
		t = math.max(t, 0)
		local c = workspace.CurrentCamera
		c.CameraType = Enum.CameraType.Scriptable

		-- the camera, shaking
		local cf, fov = T.Camera(t)
		local k = T.Shake(t)
		if k > 0 then
			local n = os.clock() * 22
			local big = t >= T.IMPACT and 4 or 1.5
			cf = cf * CFrame.new(math.noise(n, 3.1) * k * big, math.noise(n, 8.7) * k * big, 0)
				* CFrame.Angles(math.noise(n, 1.9) * k * 0.02, math.noise(n, 6.6) * k * 0.02, math.noise(n, 5.3) * k * 0.04)
		end
		c.CFrame = cf
		c.FieldOfView = fov

		-- the dragon and its pool
		local body = dragon.place(t)
		pool.draw(t)

		-- the sounds, on cue
		once("start", function() sfx("Lava"); sfx("Rumble"); sfx("RoarAlt") end)
		if t >= T.EST_END - T.CUT then once("cut", function() sfx("Whoosh") end) end
		if t >= T.BURST then once("burst", function()
			sfx("BoomLayer"); sfx("Rumble"); sfx("Roar2"); sfx("Flap")
			-- lava flung everywhere as it bursts out
			Kit.burst(pool.lava, 90, {
				Texture = SPARK_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
				Size = seq({ { 0, 16 }, { 1, 6 } }), Lifetime = NumberRange.new(1.5, 2.5),
				Speed = NumberRange.new(150, 300), SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, -220, 0),
				EmissionDirection = Enum.NormalId.Right,
			})
			Kit.burst(pool.lava, 30, {
				Texture = FIRE_TEX, Color = cseq(HOT, DEEP), LightEmission = 1, LightInfluence = 0,
				Size = seq({ { 0, 50 }, { 1, 110 } }), Transparency = seq({ { 0, 0 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(100, 200), SpreadAngle = Vector2.new(30, 30),
				EmissionDirection = Enum.NormalId.Right, Drag = 2,
			})
		end) end
		if t >= T.HOVER_AT + 0.1 then once("roar", function() sfx("Roar"); sfx("Bass") end) end
		if t >= T.SWEEP then once("dive", function() sfx("Whoosh"); fade("Lava", 1.5) end) end
		if t >= T.BREATH_ON then once("fire", function() sfx("Fire") end) end
		if t >= T.BREATH_OFF then once("fireOff", function() fade("Fire", 0.6) end) end
		if t >= T.CHARGE then once("charge", function() sfx("Rumble"); sfx("RoarAlt") end) end
		if t >= T.HUSH then once("hush", function()
			for _, name in ipairs({ "Lava", "Flap", "Fire", "Rumble", "RoarAlt", "Roar2", "Bass" }) do fade(name, 0.2) end
		end) end
		if t >= T.SPIT then once("spit", function() sfx("Whoosh"); sfx("Fire", 0.3) end) end

		-- the breath, and the course burning where it lands
		local b = T.Breath(t)
		if b > 0 then
			local from = dragon.mouth.Position
			local flat = body.LookVector * Vector3.new(1, 0, 1)
			flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
			local aim = (flat + Vector3.new(0, -1.15, 0)).Unit
			breathAt.WorldCFrame = CFrame.lookAt(from, from + aim)
			breath.Rate = 260 * b
			breathCore.Rate = 120 * b
			breathLight.Brightness = 8 * b
			-- where it lands: the ground, or the sea (rays go through the water)
			local landAt, landNormal
			local hit = workspace:Raycast(from, aim * 1200, rayParams)
			if hit and hit.Position.Y >= T.SEA then
				landAt, landNormal = hit.Position, hit.Normal
			elseif aim.Y < 0 and from.Y > T.SEA then
				local at = from + aim * ((from.Y - T.SEA) / -aim.Y)
				if (at - from).Magnitude < 1200 then landAt, landNormal = at, Vector3.yAxis end
			end
			local reach = landAt and (landAt - from).Magnitude or 500
			local flick = 1 + 0.12 * math.sin(os.clock() * 37) + 0.08 * math.sin(os.clock() * 23)
			for i, seg in ipairs(jet) do
				local a, z = reach * (i - 1) / 3, reach * i / 3
				local mid = from + aim * ((a + z) / 2)
				local along = CFrame.lookAt(mid, mid + aim) * CFrame.Angles(0, math.rad(90), 0)
				local w = (6 + 12 * i) * b * flick
				seg.core.Size = Vector3.new(z - a + 2, w * 0.45, w * 0.45)
				seg.core.CFrame = along
				seg.core.Transparency = 0.1 + 0.15 * (i - 1)
				seg.fire.Size = Vector3.new(z - a + 2, w, w)
				seg.fire.CFrame = along
				seg.fire.Transparency = 0.35 + 0.1 * (i - 1)
			end
			if landAt then
				splash.Size = Vector3.one * 60 * b * flick
				splash.CFrame = CFrame.new(landAt)
				splash.Transparency = 0.3
			else
				splash.Transparency = 1
			end
			if landAt and b > 0.5 and t >= nextFire and fires < MAX_FIRES then
				nextFire = t + FIRE_EVERY
				fires += 1
				burnAt(home, landAt, landNormal)
			end
		else
			breath.Rate, breathCore.Rate, breathLight.Brightness = 0, 0, 0
			for _, seg in ipairs(jet) do seg.core.Transparency, seg.fire.Transparency = 1, 1 end
			splash.Transparency = 1
		end

		-- the fireball: growing in its jaws, then falling onto the middle of the map
		if t >= T.CHARGE and t < T.IMPACT then
			local size, pos
			if t < T.SPIT then
				size = 8 + 52 * T.Charge(t)
				pos = dragon.mouth.Position + body.LookVector * size * 0.3
			else
				size = 60 + 30 * T.Fall(t)
				pos = spitFrom:Lerp(T.GROUND_ZERO, T.Fall(t) ^ 1.3)
			end
			fireball.Size = Vector3.one * size * (1 + 0.06 * math.sin(t * 40))
			fireball.CFrame = CFrame.new(pos)
			fireball.Transparency = 0
			fireball.Color = HOT:Lerp(Color3.new(1, 1, 1), 0.3 + 0.3 * math.sin(t * 25))
			ballFire.Rate = 90
			ballLight.Brightness = 10
		else
			fireball.Transparency, ballFire.Rate, ballLight.Brightness = 1, 0, 0
		end

		-- THE BLAST
		if t >= T.IMPACT then
			once("boom", function()
				sfx("Boom"); sfx("BoomLayer"); sfx("Bass")
				task.delay(1.2, function() if s.alive then sfx("Rumble") end end)
				task.delay(2.2, function() if s.alive then sfx("Roar") end end)
				blast = buildBlast(home)
			end)
			blast.draw(t - T.IMPACT)
		end

		-- the world's colour: a hot red glow, flaring with the roar; then white-hot, then burning orange
		if t < T.IMPACT then
			local pulse = 0.5 + 0.5 * math.sin(t * 3)
			local roar = (t > T.HOVER_AT and t < T.SWEEP) and 0.35 or 0
			grade.TintColor = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 175, 140), 0.35 + 0.3 * pulse + roar)
			grade.Saturation = 0.15
			grade.Contrast = 0.1
			grade.Brightness = 0
			heatGlow.BackgroundTransparency = 1 - (0.25 + 0.2 * pulse + roar * 0.5) * T.Clamp01(t / 1.5)
		else
			local a = t - T.IMPACT
			grade.Brightness = 0.55 * (1 - T.Clamp01(a / 1.5))
			grade.Contrast = 0.2
			grade.TintColor = Color3.fromRGB(255, 250, 235):Lerp(Color3.fromRGB(255, 160, 110), T.Clamp01(a / 2))
			grade.Saturation = 0.2
			heatGlow.BackgroundTransparency = 1 - 0.4 * (1 - T.Clamp01(a / 4))
		end

		-- the words: the warning flashing until the flight, the buyer's line with it
		local showWords = t < T.SWEEP
		warning.Visible = showWords
		warning.TextTransparency = math.sin(t * 6) > -0.4 and 0 or 0.6
		warning.UIStroke.Transparency = warning.TextTransparency
		byLine.Visible = showWords

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

Remotes:WaitForChild("DragonAlert").OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or type(info.Start) ~= "number" then return end
	-- the death popup has the camera (its frozen view and its buttons): this one sits it out
	if next(game:GetService("ContextActionService"):GetBoundActionInfo("DeathCameraNoControls")) ~= nil then return end
	-- a second one while this one plays waits its turn on the server; never two at once here
	if playing then return end
	local ok, err = pcall(play, info)
	if not ok then
		warn("[Dragon] " .. tostring(err))
		-- it broke part-way: everything it took (controls, screens, camera) comes back now
		if current and current.alive then current:Finish() end
		playing = false
	end
end)
