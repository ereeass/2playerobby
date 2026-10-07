--=====================================================================
-- NukeCinematic   (StarterGui.NukeGui)
--
-- NUKE ALL as THIS player sees it - every player in the server gets it, on the same clock
-- (Remotes.NukeAlert { By, Start }: ScooterSystem.NukeAll; every time, shot and size is in
-- ReplicatedStorage.TrollFx.NukeTimeline). A disaster-movie cutscene:
--   the whole map        a slow push in over the whole obby; sirens, a rumble, red warning
--                        light, NUCLEAR LAUNCH DETECTED / <buyer> bought NUKE ALL!
--   the nuke             (a cut through black) close up, hanging nose-down high over the
--                        middle of the map, circling it; its warning light flashing, beeps
--   the fall             the camera pulls right back out and it falls, faster and faster,
--                        trailing fire and smoke; 3.. 2.. 1..; the sirens cut to dead silence
--   the explosion        a white flash, a fireball, an orange heat dome over the whole map, a
--                        shockwave racing out across all of it, a mushroom cloud rising, the
--                        camera thrown about, the world lit orange
--   the end              a fade to black; everything comes back, and the game carries on
--                        (the rides' death popups, the lobby's respawn: ScooterSystem.NukeAll)
-- While it plays every other screen of the player's is put away and every control and menu
-- locked (FinishCutscene.Lock, as the trolls and the finish cutscene do); all of it comes back
-- at the end. EVERYTHING here is this machine's own picture: the map itself is never touched.
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
local T        = require(fx:WaitForChild("NukeTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local template = fx:WaitForChild("NukeModel")
local soundsOf = fx:WaitForChild("NukeSounds")
local Remotes  = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local cutscene = player:WaitForChild("PlayerScripts"):WaitForChild("FinishCutscene")
local Lock     = require(cutscene:WaitForChild("Lock"))
local HIDE_CORE = require(cutscene:WaitForChild("Config")).HideCoreGui
local HudSync  = require(RS:WaitForChild("HudSync"))

-- tell the server once this player is fully in (loading screen and first-join intro done):
-- until then a show's end never knocks them down (ScooterSystem.NukeAll)
HudSync.WhenIntroDone(function()
	local readyRemote = Remotes:WaitForChild("PlayerReady", 30)
	if readyRemote then readyRemote:FireServer() end
end)
local seq, cseq = Kit.seq, Kit.cseq

local CAM_STEP   = "NukeCinematic"
local CAM_PRI    = Enum.RenderPriority.Last.Value + 100   -- over every other camera in the game
local FONT       = Font.new("rbxasset://fonts/families/FredokaOne.json")
local RED        = Color3.fromRGB(255, 45, 45)
local YELLOW     = Color3.fromRGB(255, 221, 0)
local FIRE       = Color3.fromRGB(255, 170, 60)
local EMBER      = Color3.fromRGB(255, 80, 25)
local SMOKE      = Color3.fromRGB(95, 85, 85)
local LETTERBOX_MAX = 0.075   -- the black bars, top and bottom: at most this share of the screen's height each
local CINEMA = 2              -- the bars only crop the screen to a CINEMA : 1 frame (as the finish cutscene's
                              -- FinishCutscene.Fade): wide phones get none, 16:9 screens slim ones
local LETTERBOX = LETTERBOX_MAX   -- this screen's, worked out as each cinematic starts (fitBars)
local RETURN_FADE = 0.5    -- black -> the game, once everything is back

---------------------------------------------------------------- session
-- Everything taken registers how to give it back; given back once, in reverse (the same
-- contract as FinishCutscene's Lock and TrolledUI).
local Session = {}
Session.__index = Session
function Session.new() return setmetatable({ tasks = {}, alive = true }, Session) end
function Session:Add(name, fn) table.insert(self.tasks, { name = name, fn = fn }) end
function Session:Finish()
	if not self.alive then return end
	self.alive = false
	for i = #self.tasks, 1, -1 do
		local ok, err = pcall(self.tasks[i].fn)
		if not ok then warn("[Nuke] putting back '" .. self.tasks[i].name .. "' failed: " .. tostring(err)) end
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
local redGlow = frame("RedGlow", { BackgroundColor3 = RED, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 })
do
	local g = Instance.new("UIGradient")   -- red at the edges, clear in the middle
	g.Transparency = seq({ { 0, 0 }, { 0.25, 0.85 }, { 0.75, 0.85 }, { 1, 0 } })
	g.Parent = redGlow
end
local warning = label("Warning", {
	Text = "\u{26A0} NUCLEAR LAUNCH DETECTED \u{26A0}", TextColor3 = RED, Visible = false, ZIndex = 5,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, LETTERBOX + 0.03), Size = UDim2.fromScale(0.8, 0.075),
}, Color3.new(0, 0, 0), 3)
local byLine = label("By", {
	Text = "", TextColor3 = YELLOW, Visible = false, ZIndex = 5,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, LETTERBOX + 0.11), Size = UDim2.fromScale(0.6, 0.05),
}, Color3.new(0, 0, 0), 1.5)
local countdown, countStroke = label("Countdown", {
	Text = "", TextColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 5,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.78), Size = UDim2.fromScale(0.3, 0.16),
}, Color3.fromRGB(120, 0, 0), 4)
local countScale = Instance.new("UIScale")
countScale.Parent = countdown
-- the bars (and the words just under the top one) fitted to this screen's shape
local function fitBars()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	LETTERBOX = (vp and vp.X > 0 and vp.Y > 0) and math.clamp((1 - (vp.X / vp.Y) / CINEMA) / 2, 0, LETTERBOX_MAX) or LETTERBOX_MAX
	top.Size, bottom.Size = UDim2.fromScale(1, LETTERBOX), UDim2.fromScale(1, LETTERBOX)
	top.Position, bottom.Position = UDim2.fromScale(0, -LETTERBOX), UDim2.fromScale(0, 1)
	warning.Position = UDim2.fromScale(0.5, LETTERBOX + 0.03)
	byLine.Position = UDim2.fromScale(0.5, LETTERBOX + 0.11)
end
local white = frame("Flash", { BackgroundColor3 = Color3.fromRGB(255, 250, 235), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
local black = frame("Black", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
for _, c in ipairs(gui:GetChildren()) do if c:IsA("GuiObject") then c.Visible = c.Name ~= "Warning" and c.Name ~= "By" and c.Name ~= "Countdown" end end

---------------------------------------------------------------- the explosion
local UP = CFrame.Angles(0, 0, math.rad(90))   -- a cylinder standing up / lying flat

local function piece(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- Everything the blast is made of, built at the impact; draw(s) places it s seconds after
local function buildBlast(home)
	local gz = T.GROUND_ZERO
	local b = {}
	b.core = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), Size = Vector3.one }, home)
	b.fire = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = FIRE, Size = Vector3.one }, home)
	b.heat = piece({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 140, 50), Transparency = 1, Size = Vector3.one }, home)
	b.ring = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 235, 190), Size = Vector3.one }, home)
	b.dust = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(205, 185, 160), Size = Vector3.one }, home)
	b.stem = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = FIRE, Size = Vector3.one }, home)
	b.cap  = piece({ Material = Enum.Material.SmoothPlastic, Color = FIRE, Size = Vector3.one }, home)
	local capMesh = Instance.new("SpecialMesh")
	capMesh.MeshType = Enum.MeshType.Sphere
	capMesh.Parent = b.cap
	b.capMesh = capMesh
	b.skirt = piece({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = SMOKE, Size = Vector3.one }, home)
	-- smoke billowing off the cap and up the stem
	for _, host in ipairs({ b.cap, b.stem }) do
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = cseq(Color3.fromRGB(255, 150, 70), SMOKE)
		e.Size = seq({ { 0, host == b.cap and 60 or 30 }, { 1, host == b.cap and 140 or 70 } })
		e.Transparency = seq({ { 0, 0.3 }, { 0.7, 0.6 }, { 1, 1 } })
		e.Lifetime = NumberRange.new(3, 5)
		e.Speed = NumberRange.new(10, 30)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-20, 20)
		e.SpreadAngle = Vector2.new(180, 180)
		e.LightInfluence = 0.3
		e.Rate = host == b.cap and 25 or 12
		e.Parent = host
	end
	-- the first burst: fire, sparks and chunks flung out from the middle
	local point = piece({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(gz + Vector3.new(0, 30, 0)) }, home)
	Kit.burst(point, 60, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = cseq(Color3.fromRGB(255, 230, 140), EMBER), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 40 }, { 0.5, 90 }, { 1, 0 } }), Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(120, 220), Drag = 2,
	})
	Kit.burst(point, 120, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = cseq(Color3.fromRGB(255, 245, 170), EMBER), LightEmission = 1, LightInfluence = 0,
		Size = seq({ { 0, 8 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(200, 380), Drag = 1.5,
		Acceleration = Vector3.new(0, -80, 0),
	})
	Kit.burst(point, 40, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = cseq(Color3.fromRGB(150, 130, 120), SMOKE),
		Size = seq({ { 0, 60 }, { 1, 160 } }), Transparency = seq({ { 0, 0.2 }, { 0.8, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(80, 160), Drag = 2.5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), LightInfluence = 0.4,
	})
	local light = Instance.new("PointLight")
	light.Color = FIRE
	light.Range = 60
	light.Brightness = 20
	light.Parent = point
	TweenService:Create(light, TweenInfo.new(3), { Brightness = 0 }):Play()

	function b.draw(s)
		-- the white-hot core, then the fireball swelling and cooling
		local k = T.Clamp01(s / 0.4)
		b.core.Size = Vector3.one * (20 + 240 * k)
		b.core.CFrame = CFrame.new(gz)
		b.core.Transparency = k
		local f = T.Clamp01(s / 1.4)
		local r = T.FIREBALL * (1 - (1 - f) ^ 3)
		b.fire.Size = Vector3.one * math.max(r * 2, 1)
		b.fire.CFrame = CFrame.new(gz + Vector3.new(0, r * 0.35, 0))
		b.fire.Color = FIRE:Lerp(EMBER, T.Clamp01(s / 2.5))
		b.fire.Transparency = s < 1.2 and 0.05 or math.min(0.05 + (s - 1.2) / 1.6, 1)
		-- the heat dome: over the whole map for a moment
		local h = T.Clamp01(s / 1.1)
		b.heat.Size = Vector3.one * math.max(T.HEAT * 2 * (1 - (1 - h) ^ 2), 1)
		b.heat.CFrame = CFrame.new(gz)
		b.heat.Transparency = s < 1.1 and 0.55 or math.min(0.55 + (s - 1.1) / 2.2 * 0.45, 1)
		-- the shockwave racing out over everything, and the dust ring behind it
		local w = T.Clamp01(s / 2.4)
		local wr = T.SHOCKWAVE * w ^ 0.6
		b.ring.Size = Vector3.new(3, math.max(wr * 2, 1), math.max(wr * 2, 1))
		b.ring.CFrame = CFrame.new(gz + Vector3.new(0, 3, 0)) * UP
		b.ring.Transparency = 0.1 + 0.9 * w
		local d = T.Clamp01(s / 3.6)
		local dr = T.SHOCKWAVE * 0.85 * d ^ 0.55
		b.dust.Size = Vector3.new(18, math.max(dr * 2, 1), math.max(dr * 2, 1))
		b.dust.CFrame = CFrame.new(gz + Vector3.new(0, 9, 0)) * UP
		b.dust.Transparency = 0.25 + 0.75 * d
		-- the mushroom cloud rising
		local m = T.Clamp01((s - 0.3) / 4.5)
		local rise = T.STEM * (1 - (1 - m) ^ 2)
		local cool = T.Clamp01(s / 4)
		local stemW = 70 + 20 * m
		b.stem.Size = Vector3.new(math.max(rise, 1), stemW, stemW)
		b.stem.CFrame = CFrame.new(gz + Vector3.new(0, rise / 2, 0)) * UP
		b.stem.Color = FIRE:Lerp(SMOKE, cool)
		b.stem.Transparency = m <= 0 and 1 or 0.08
		local capR = T.CAP * (0.3 + 0.7 * math.sqrt(m))
		b.capMesh.Scale = Vector3.new(capR * 2, capR * 1.15, capR * 2)
		b.cap.CFrame = CFrame.new(gz + Vector3.new(0, rise + capR * 0.2, 0))
		b.cap.Color = Color3.fromRGB(255, 190, 90):Lerp(SMOKE, cool)
		b.cap.Transparency = m <= 0 and 1 or 0
		b.skirt.Size = Vector3.new(capR * 0.3, capR * 2.5, capR * 2.5)
		b.skirt.CFrame = CFrame.new(gz + Vector3.new(0, rise - capR * 0.25, 0)) * UP
		b.skirt.Color = Color3.fromRGB(230, 130, 70):Lerp(SMOKE, cool)
		b.skirt.Transparency = m <= 0 and 1 or 0.55
	end
	return b
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

	-- the world's colour
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "NukeGrade"
	grade.Parent = Lighting
	s:Add("colour", function() grade:Destroy() end)

	-- this machine's pieces: the nuke, its trail, the blast
	local home = Instance.new("Folder")
	home.Name = "NukeCinematic"
	home.Parent = Kit.mine()
	s:Add("pieces", function() home:Destroy() end)
	local nuke = template:Clone()
	nuke.Parent = home
	local hull = nuke.PrimaryPart or nuke:FindFirstChild("Hull")
	local warnLight = nuke:FindFirstChild("WarningLight")
	local redLight = Instance.new("PointLight")
	redLight.Color = RED
	redLight.Range = 60
	redLight.Brightness = 0
	redLight.Parent = hull
	local glow = Instance.new("Highlight")
	glow.FillColor = RED
	glow.FillTransparency = 1
	glow.OutlineColor = Color3.fromRGB(255, 120, 80)
	glow.OutlineTransparency = 0.3
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = nuke
	-- fire and smoke pouring off its tail as it falls (its tail is +Z of the hull)
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, 0, T.NUKE_HALF * 0.9)
	tail.Parent = hull
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.Color = cseq(Color3.fromRGB(255, 190, 110), Color3.fromRGB(120, 115, 115))
	trail.Size = seq({ { 0, 16 }, { 1, 60 } })
	trail.Transparency = seq({ { 0, 0.2 }, { 1, 1 } })
	trail.Lifetime = NumberRange.new(1.5, 2.2)
	trail.Speed = NumberRange.new(2, 6)
	trail.SpreadAngle = Vector2.new(15, 15)
	trail.EmissionDirection = Enum.NormalId.Back
	trail.LightEmission = 0.4
	trail.Rate = 0
	trail.Parent = tail
	local flame = Instance.new("ParticleEmitter")
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.Color = cseq(Color3.fromRGB(255, 240, 170), EMBER)
	flame.Size = seq({ { 0, 14 }, { 1, 0 } })
	flame.Lifetime = NumberRange.new(0.3, 0.5)
	flame.Speed = NumberRange.new(10, 20)
	flame.EmissionDirection = Enum.NormalId.Back
	flame.LightEmission = 1
	flame.Rate = 0
	flame.Parent = tail

	-- the sounds, heard as if right there (2D: they play on the screen)
	local sounds = {}
	for _, snd in ipairs(soundsOf:GetChildren()) do
		if snd:IsA("Sound") then
			local c = snd:Clone()
			c.Parent = gui
			sounds[snd.Name] = c
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
	local function play(name, at)
		local c = sounds[name]
		if not c then return end
		c.TimePosition = at or 0
		c:Play()
	end
	local function fade(name, dur)
		local c = sounds[name]
		if c and c.IsPlaying then TweenService:Create(c, TweenInfo.new(dur), { Volume = 0 }):Play() end
	end

	-- the screen
	byLine.Text = ('%s bought <font color="#FFFFFF">NUKE ALL!</font>'):format((tostring(info.By or "Someone"):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")))
	byLine.RichText = true
	warning.Visible, byLine.Visible = true, true
	fitBars()
	local barIn = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, barIn, { Position = UDim2.fromScale(0, 0) }):Play()
	TweenService:Create(bottom, barIn, { Position = UDim2.fromScale(0, 1 - LETTERBOX) }):Play()
	s:Add("screen", function()
		warning.Visible, byLine.Visible, countdown.Visible = false, false, false
		top.Position, bottom.Position = UDim2.fromScale(0, -LETTERBOX), UDim2.fromScale(0, 1)
		redGlow.BackgroundTransparency, white.BackgroundTransparency = 1, 1
	end)

	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	local nextBeep = T.EST_END
	local blast
	local lastCount

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

		-- the sounds, on cue
		once("sirens", function()
			play("Siren"); play("Siren2"); play("Rumble")
		end)
		if t >= T.EST_END - T.CUT then once("cut", function() play("Whoosh") end) end
		if t >= T.CLOSE_END then once("pull", function() play("Whoosh") end) end
		if t >= T.FALL_START then
			once("whistle", function()
				local w = sounds.Whistle
				local len = w and w.TimeLength or 0
				play("Whistle", math.max(len - (T.IMPACT - T.FALL_START), 0))
			end)
		end
		if t >= T.HUSH then
			once("hush", function()
				fade("Siren", 0.15); fade("Siren2", 0.15); fade("Rumble", 0.15); fade("Whistle", 0.3)
			end)
		end
		if t >= T.EST_END and t < T.HUSH and t >= nextBeep then
			nextBeep = t + (t < T.FALL_START and 0.7 or 0.3)
			play("Beep")
		end

		-- the nuke: its warning light and red glow flashing with the beeps, fire off its tail
		if t < T.IMPACT then
			nuke:PivotTo(T.Nuke(t))
			local blink = (math.sin(t * 9) > 0) and 1 or 0.15
			redLight.Brightness = 4 * blink
			if warnLight then warnLight.Color = blink > 0.5 and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(90, 10, 10) end
			glow.OutlineTransparency = 0.2 + 0.6 * (1 - blink)
			local falling = T.Fall(t)
			trail.Rate = falling > 0 and 60 or 0
			flame.Rate = falling > 0 and 80 or 0
		else
			once("gone", function()
				for _, p in ipairs(nuke:GetDescendants()) do
					if p:IsA("BasePart") then p.LocalTransparencyModifier = 1 end
				end
				glow.Enabled = false
				trail.Rate, flame.Rate, redLight.Brightness = 0, 0, 0
			end)
		end

		-- THE BLAST
		if t >= T.IMPACT then
			once("boom", function()
				play("Boom"); play("BoomLayer"); play("Bass")
				task.delay(1.2, function() if s.alive then play("Rumble") end end)
				blast = buildBlast(home)
			end)
			blast.draw(t - T.IMPACT)
		end

		-- the world's colour: a red warning pulse, then white-hot, then burnt orange
		if t < T.IMPACT then
			local pulse = 0.5 + 0.5 * math.sin(t * 4)
			grade.TintColor = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 190, 190), 0.4 + 0.4 * pulse)
			grade.Saturation = -0.1
			grade.Brightness = 0
			redGlow.BackgroundTransparency = 1 - 0.35 * pulse
		else
			local a = t - T.IMPACT
			grade.Brightness = 0.6 * (1 - T.Clamp01(a / 1.5))
			grade.Contrast = 0.2
			grade.TintColor = Color3.fromRGB(255, 255, 240):Lerp(Color3.fromRGB(255, 185, 140), T.Clamp01(a / 2))
			grade.Saturation = 0.1
			redGlow.BackgroundTransparency = 1
		end

		-- the words: the warning flashing, then the countdown
		warning.TextTransparency = (t < T.IMPACT and math.sin(t * 8) > -0.3) and 0 or 1
		warning.UIStroke.Transparency = warning.TextTransparency
		byLine.Visible = t < T.CLOSE_END   -- out of the way of the falling nuke
		local left = T.IMPACT - t
		if t >= T.FALL_START and left > 0 then
			local n = math.ceil(left)
			countdown.Visible = true
			countdown.Text = tostring(n)
			if n ~= lastCount then
				lastCount = n
				countScale.Scale = 1.6
				TweenService:Create(countScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		else
			countdown.Visible = false
		end

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

Remotes:WaitForChild("NukeAlert").OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or type(info.Start) ~= "number" then return end
	-- the death popup has the camera (its frozen view and its buttons): this one sits it out
	if next(game:GetService("ContextActionService"):GetBoundActionInfo("DeathCameraNoControls")) ~= nil then return end
	-- a second one while this one plays waits its turn on the server; never two at once here
	if playing then return end
	local ok, err = pcall(play, info)
	if not ok then
		warn("[Nuke] " .. tostring(err))
		-- it broke part-way: everything it took (controls, screens, camera) comes back now
		if current and current.alive then current:Finish() end
		playing = false
	end
end)
