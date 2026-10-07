--[[ LoadingClient

First-join loading screen and spawn fly-down. Runs once per session, on this
player's own client only: nothing here talks to the server or to other players.

  1  The Background picture covers the screen with "Loading assets" and a
     counter at the bottom while AssetLoader genuinely preloads the game's
     assets. The counter follows the real progress, paced so it counts up
     evenly, and the loading phase always ends LOAD_TIME seconds after the
     screen appears. That timer is its only finish line: nothing it waits on
     can hang, and an asset that never answers is simply written off.
  2  "CLICK ANYWHERE TO CONTINUE" then shows (as soon as the character exists).
  3  On click the picture melts into the live world, seen from the same angle,
     and the camera flies down to the character. The last frame is exactly where
     Roblox's own camera takes over, then this script lets go completely.

Background music is left out on purpose: MusicController loads each song just
before it plays.

CHANGING THE PICTURE
  Select LoadingGui > Background and paste the new image into Image. For a
  seamless blend its attributes must describe the view the picture shows:
    CameraPosition / CameraLookAt   where it was taken from / looking at
    CameraFOV                       its vertical field of view (degrees)
    ImageAspect                     its width / height
  With no picture (or one that fails to load in time) the live 3D view from
  that camera is shown instead.
]]

local Players           = game:GetService("Players")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local StarterPlayer     = game:GetService("StarterPlayer")

local AssetLoader = require(script.Parent:WaitForChild("AssetLoader"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LOAD_TIME      = 1.5            -- the blurred opening view holds at least this long before the fly-down
local NO_CHARACTER_LIMIT = 12         -- no live character this long after loading: hand the camera over anyway
local LATE_CHARACTER_LIMIT = 45     -- ...then still hold the opening view this much longer for a late one
local MIN_COUNT_TIME = 0.8            -- ... though the counter always gets at least this long to count up
local FLIGHT_TIME    = 2.6            -- click -> hand-off, seconds
local BLEND_TIME     = 0.3            -- then ease into Roblox's own camera
local WIND_FROM      = 0.45           -- flight progress where the rushing wind starts; it builds from there...
local WIND_FULL      = 0.9            -- ...to its fullest as the camera slows into place behind the player
local WIND_FADE      = 1.2            -- then it dies away over this, once the player can move
local SHAKE_DEG      = 0.6            -- camera buffeting at full wind, degrees; it follows the wind's volume
local FOV_SWELL      = 6              -- extra degrees of FOV mid-flight
local END_ZOOM       = 12.5           -- Roblox's default camera distance ...
local END_PITCH      = math.rad(15)   -- ... and its default downward tilt
local PEAK_PITCH     = math.rad(45)   -- steepest look-down mid-flight: keeps the path above the trees

local CAMERA_STEP = Enum.RenderPriority.Camera.Value + 1   -- runs right after Roblox's camera
local HOLD, FLY, BLEND = "LoadingHold", "LoadingFly", "LoadingBlend"

---------------------------------------------------------------- screen
local gui     = script.Parent:WaitForChild("LoadingGui"):Clone()
local cover   = gui:WaitForChild("Cover")
local bg      = gui:WaitForChild("Background")
local shade   = gui:WaitForChild("Shade")
local status  = gui:WaitForChild("Status")
local counter = gui:WaitForChild("Counter")
local hint    = gui:WaitForChild("Continue")
local catcher = gui:WaitForChild("ClickCatcher")
local wind    = gui:FindFirstChild("Wind")     -- rushing air as the camera closes in (its Volume = the loudest it gets)
local windPeak = wind and wind.Volume or 0

bg.ImageTransparency = 1
hint.TextTransparency = 1
status.Text, counter.Text = "Loading assets", ""
-- No loading screen: the live world shows straight away (softly blurred), then the camera
-- flies down to the character on its own. The GUI is never shown; its Wind sound is still
-- used for the fly-down. (The old screen is archived in ServerStorage > Loading Fix Backups.)
ReplicatedFirst:RemoveDefaultLoadingScreen()

local function tween(o, time, props, style, dir)
	local t = TweenService:Create(o, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

---------------------------------------------------------------- the "still loading" blur
-- While the screen is up the view is a little soft, and it sharpens as the camera starts to
-- fly down, so the click feels like the world finishing loading into focus. A picture can't
-- be blurred by Roblox's BlurEffect (that only softens the 3D world), so the picture gets a
-- few faint copies of itself laid over it a few pixels off in a ring - a gentle blur - and the
-- live 3D view (shown when there's no picture, and under the picture as it melts away) gets
-- a matching BlurEffect. Both ease away together on the click.
local BLUR_PX      = 3       -- the picture's blur: how far the copies sit off, in pixels (at 1080 tall)
local BLUR_COPIES  = 8       -- copies in the ring
local BLUR_ALPHA   = 0.8     -- each copy's ImageTransparency (at full blur)
local BLUR_3D      = 10      -- the 3D view's BlurEffect size to match
local UNBLUR_TIME  = 0.5     -- click -> sharp

local blurAmount = Instance.new("NumberValue")   -- 1 = soft, 0 = sharp
blurAmount.Value = 1
local worldBlur = Instance.new("BlurEffect")
worldBlur.Name = "LoadingBlur"
worldBlur.Size = BLUR_3D
worldBlur.Parent = workspace.CurrentCamera or game:GetService("Lighting")
local blurCopies = {}
for i = 1, BLUR_COPIES do
	local a = (i / BLUR_COPIES) * math.pi * 2
	local copy = Instance.new("ImageLabel")
	copy.Name = "BlurCopy"
	copy.BackgroundTransparency = 1
	copy.Image = bg.Image
	copy.ScaleType = bg.ScaleType
	copy.ImageTransparency = 1
	copy.AnchorPoint = Vector2.new(0.5, 0.5)
	copy.Size = UDim2.fromScale(1, 1)
	copy.ZIndex = bg.ZIndex
	copy.Parent = bg
	blurCopies[i] = { label = copy, dir = Vector2.new(math.cos(a), math.sin(a)) }
end
local function drawBlur()
	local k = blurAmount.Value
	local cam = workspace.CurrentCamera
	local px = BLUR_PX * k * ((cam and cam.ViewportSize.Y or 1080) / 1080)
	-- each copy shows only as much as the picture itself does
	local shown = 1 - bg.ImageTransparency
	for _, c in ipairs(blurCopies) do
		c.label.Position = UDim2.new(0.5, c.dir.X * px, 0.5, c.dir.Y * px)
		c.label.ImageTransparency = 1 - (1 - BLUR_ALPHA) * shown * k
	end
	worldBlur.Size = BLUR_3D * k
end
bg:GetPropertyChangedSignal("ImageTransparency"):Connect(drawBlur)
blurAmount.Changed:Connect(drawBlur)
drawBlur()
local function unblur()
	TweenService:Create(blurAmount, TweenInfo.new(UNBLUR_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = 0 }):Play()
	task.delay(UNBLUR_TIME + 0.1, function() worldBlur:Destroy() end)
end

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

---------------------------------------------------------------- camera: the picture's view
local camPos    = bg:GetAttribute("CameraPosition") or Vector3.new(-270.43, 280.09, 338.40)
local camLookAt = bg:GetAttribute("CameraLookAt")   or Vector3.new(-105.45, 197.11, 261.60)
local picFov    = math.rad(bg:GetAttribute("CameraFOV") or 70)
local picAspect = bg:GetAttribute("ImageAspect")    or 16 / 9

while not workspace.CurrentCamera do workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() end
local baseFov = workspace.CurrentCamera.FieldOfView   -- the game's normal FOV, restored at the end

-- The picture fills the screen by cropping, so on a screen wider than the picture
-- less of it shows top to bottom; the matching 3D view narrows the same way.
local function pictureFov(cam)
	local vp = cam.ViewportSize
	local visible = vp.Y > 0 and math.min(1, picAspect / (vp.X / vp.Y)) or 1
	return math.deg(2 * math.atan(math.tan(picFov / 2) * visible))
end

-- Held until the click. Scriptable switches Roblox's camera off; setting it every
-- frame means nothing else can move it in the meantime.
local startCF = CFrame.lookAt(camPos, camLookAt)
RunService:BindToRenderStep(HOLD, CAMERA_STEP, function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	cam.CFrame, cam.Focus = startCF, CFrame.new(camLookAt)
	cam.FieldOfView = pictureFov(cam)
end)

---------------------------------------------------------------- hold the player until the hand-off
-- Walking and jumping are the PlayerModule's CharacterContext (the ride controls
-- switch the same context off while riding; nobody can be riding yet). The invite
-- button would sit on top of the cinematic, so it waits too.
local released = false
local characterContext
local hiddenGuis = {}

task.spawn(function()
	local pm       = StarterPlayer:WaitForChild("PlayerModule", 60)
	local contexts = pm and pm:WaitForChild("InputContexts", 60)
	local ctx      = contexts and contexts:WaitForChild("CharacterContext", 60)
	if ctx and ctx:IsA("InputContext") and ctx.Enabled and not released then
		ctx.Enabled = false
		characterContext = ctx
	end
end)

local function hideGui(g)
	if g.Name == "InviteGui" and g:IsA("ScreenGui") and g.Enabled then
		g.Enabled = false
		hiddenGuis[g] = true
	end
end
for _, g in ipairs(playerGui:GetChildren()) do hideGui(g) end
local guiAdded = playerGui.ChildAdded:Connect(hideGui)

local function release()
	if released then return end
	released = true
	guiAdded:Disconnect()
	if characterContext then characterContext.Enabled = true end
	for g in pairs(hiddenGuis) do
		if g.Parent then g.Enabled = true end
	end
	-- the one moment the lobby HUD comes in, all of it together (ReplicatedStorage.HudSync)
	playerGui:SetAttribute("IntroDone", true)
end

---------------------------------------------------------------- character
local function liveRoot()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = hum and hum.RootPart
	if root and hum.Health > 0 then return root, hum end
	return nil
end

-- `limit` (seconds): give up and return nil instead of waiting forever
local function waitForRoot(limit)
	local t0 = os.clock()
	local root, hum = liveRoot()
	while not root do
		if limit and os.clock() - t0 > limit then return nil end
		RunService.Heartbeat:Wait()
		root, hum = liveRoot()
	end
	return root, hum
end

-- The point Roblox's camera looks at on a character (CameraModule's subject position).
local function subjectPosition(hum, root)
	local offset
	if hum.RigType == Enum.HumanoidRigType.R15 then
		offset = hum.AutomaticScalingEnabled and Vector3.new(0, 1.5 + (root.Size.Y - 2) / 2, 0) or Vector3.new(0, 2, 0)
	else
		offset = Vector3.new(0, 1.5, 0)
	end
	return root.CFrame:PointToWorldSpace(offset + hum.CameraOffset)
end

---------------------------------------------------------------- assets
local function loadRoots()
	return { workspace, game:GetService("Lighting"), game:GetService("MaterialService"),
		game:GetService("SoundService"), ReplicatedStorage, playerGui }
end

-- The music tracks are not preloaded (see the top). Nothing here waits: if the
-- list is not there, nothing is skipped.
local function musicIds()
	local skip = {}
	pcall(function()
		local music = ReplicatedStorage:FindFirstChild("Music")
		local tracks = music and music:FindFirstChild("Tracks")
		if tracks then
			for _, track in ipairs(require(tracks)) do skip[tostring(track.Id)] = true end
		end
	end)
	return skip
end

local function commas(n)
	local s, k = tostring(n), 0
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

---------------------------------------------------------------- flight
-- The camera orbits a focus point that slides from the picture's centre onto the
-- character. Its distance shrinks exponentially (a steady sense of closing in),
-- it swings round behind the character the short way, and it looks down more
-- steeply mid-way so the path stays above the trees before levelling out into
-- Roblox's default view. Checked clear of the map from every corner of the spawn.
local function orbit(v)
	local d = v.Magnitude
	return d, math.atan2(v.X, v.Z), math.asin(v.Y / d)
end

local function fromOrbit(d, yaw, pitch)
	return Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)) * d
end

local d0, yaw0, pitch0 = orbit(camPos - camLookAt)

local function flightPose(e, focusEnd, facing)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.zAxis
	local yawEnd = math.atan2(-flat.X, -flat.Z)                            -- behind the character
	local swing  = (yawEnd - yaw0 + math.pi) % (2 * math.pi) - math.pi   -- the short way round
	local zoom   = math.clamp(END_ZOOM, player.CameraMinZoomDistance, player.CameraMaxZoomDistance)

	local focus = camLookAt:Lerp(focusEnd, smooth(0, 0.7, e))
	local dist  = d0 * (zoom / d0) ^ e
	local yaw   = yaw0 + swing * smooth(0.05, 0.85, e)
	local pitch = pitch0 + (PEAK_PITCH - pitch0) * smooth(0, 0.4, e)
	pitch = pitch + (END_PITCH - pitch) * smooth(0.5, 1, e)
	return focus + fromOrbit(dist, yaw, pitch), focus
end

---------------------------------------------------------------- clean-up
local function unbind(name)
	pcall(function() RunService:UnbindFromRenderStep(name) end)
end

-- A light buffeting of the camera that follows the wind's volume: it grows as the
-- wind does and dies away with it after the hand-off. It is taken off again before
-- Roblox's camera runs each frame, so it never builds up or steers the camera.
local SHAKE, SHAKE_UNDO = "LoadingShake", "LoadingShakeUndo"
local shakeCF = CFrame.identity

local function startShake()
	if not wind then return end
	local seed = math.random() * 100
	RunService:BindToRenderStep(SHAKE_UNDO, Enum.RenderPriority.Camera.Value - 1, function()
		local cam = workspace.CurrentCamera
		if cam then cam.CFrame = cam.CFrame * shakeCF:Inverse() end
		shakeCF = CFrame.identity
	end)
	RunService:BindToRenderStep(SHAKE, CAMERA_STEP + 1, function()
		local cam = workspace.CurrentCamera
		if not cam or windPeak <= 0 then return end
		local a = math.rad(SHAKE_DEG) * math.clamp(wind.Volume / windPeak, 0, 1)
		local n = os.clock() * 9
		shakeCF = CFrame.Angles(math.noise(n, seed) * a, math.noise(seed, n) * a, math.noise(n, n + seed) * a * 0.5)
		cam.CFrame = cam.CFrame * shakeCF
	end)
end

local function stopShake()
	unbind(SHAKE); unbind(SHAKE_UNDO)
	local cam = workspace.CurrentCamera
	if cam then cam.CFrame = cam.CFrame * shakeCF:Inverse() end
	shakeCF = CFrame.identity
end

-- Light wind streaks at the edges of the screen while the camera flies in: thin
-- lines rushing outward from the centre, as many and as bright as the wind is loud.
-- They stop when the player takes over; the last ones finish on their own.
local STREAK_RATE = 26      -- streaks per second at full wind
local streakGui, streakConn

local function spawnStreak(vp, level)
	local a = math.random() * math.pi * 2
	local dx, dy = math.cos(a), math.sin(a)
	local rx, ry = 0.40 + math.random() * 0.08, 0.36 + math.random() * 0.10   -- near the edges, never mid-screen
	local s = Instance.new("Frame")
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.BorderSizePixel = 0
	s.BackgroundColor3 = Color3.fromRGB(235, 243, 255)
	s.BackgroundTransparency = 1 - 0.5 * level
	s.Size = UDim2.fromOffset(math.random(70, 180), 2)
	s.Position = UDim2.fromScale(0.5 + dx * rx, 0.5 + dy * ry)
	s.Rotation = math.deg(math.atan2(dy * ry * vp.Y, dx * rx * vp.X))   -- pointing away from the centre
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = s
	s.Parent = streakGui
	local life = 0.3 + math.random() * 0.15
	TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5 + dx * (rx + 0.12), 0.5 + dy * (ry + 0.12)),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(life + 0.05, function() s:Destroy() end)
end

local function startStreaks()
	if not wind or windPeak <= 0 then return end
	streakGui = Instance.new("ScreenGui")
	streakGui.Name = "WindStreaks"
	streakGui.IgnoreGuiInset = true
	streakGui.ResetOnSpawn = false
	streakGui.DisplayOrder = gui.DisplayOrder + 1
	streakGui.Parent = playerGui
	local owed = 0
	streakConn = RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if not cam then return end
		local level = math.clamp(wind.Volume / windPeak, 0, 1)
		owed += STREAK_RATE * level * dt
		while owed >= 1 do
			owed -= 1
			spawnStreak(cam.ViewportSize, level)
		end
	end)
end

-- `finished`: also remove the streaks still on screen
local function stopStreaks(finished)
	if streakConn then streakConn:Disconnect(); streakConn = nil end
	if finished and streakGui then streakGui:Destroy(); streakGui = nil end
end

-- Something went wrong: never leave the player stuck behind the loading screen.
local function abort(err)
	print("[Loading] intro skipped:", err)
	unbind(HOLD); unbind(FLY); unbind(BLEND)
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView = baseFov
		local _, hum = liveRoot()
		if hum then cam.CameraSubject = hum end
		cam.CameraType = Enum.CameraType.Custom
	end
	release()
	stopShake()
	stopStreaks(true)
	if wind then wind:Destroy() end
	worldBlur:Destroy()
	gui:Destroy()
end

---------------------------------------------------------------- World 1's intro cinematic
-- A player who has never seen it gets ReplicatedStorage.IntroCinematic's 5-second intro
-- instead of the fly-down (World 1 only; a place without it never waits). The server is asked
-- as the world comes in, so the answer is usually back before the opening view ends; it
-- never holds that view up more than INTRO_WAIT seconds longer.
local INTRO_WAIT = 3
local Intro, introPlay   -- the module; true / false once known

local function askIntro()
	local folder = ReplicatedStorage:FindFirstChild("IntroCinematic")
	local module = folder and folder:FindFirstChild("Intro")
	if not module then introPlay = false return end
	local ok, m = pcall(require, module)
	if not ok then warn("[Loading] intro unavailable:", m) introPlay = false return end
	local ok2, yes = pcall(m.ShouldAutoPlay)
	if ok2 and yes then
		Intro = m
		task.spawn(pcall, m.Prepare)   -- its models, sounds and the far map, while the view holds
		introPlay = true
	else
		introPlay = false
	end
end

---------------------------------------------------------------- run
local function main()
	local started = os.clock()

	-- 1  the picture, fetched in its own thread and faded in when it arrives, so a
	--    slow or broken image can never hold the loading screen up
	local picture = bg.Image ~= "" and "loading" or "none"
	if picture == "loading" then
		task.spawn(function()
			local ok = false
			pcall(function()
				ContentProvider:PreloadAsync({ bg }, function(_, s) ok = s == Enum.AssetFetchStatus.Success end)
			end)
			if picture == "loading" and (ok or bg.IsLoaded) then
				picture = "shown"
				tween(bg, 0.4, { ImageTransparency = 0 })
			end
		end)
	end

	-- 2  the world. Preloading starts the moment it is in; the map around the
	--    picture's view is asked for alongside (streaming is on) and whatever
	--    streams in during loading is picked up by the loader as it arrives.
	if not game:IsLoaded() then game.Loaded:Wait() end
	local loader = AssetLoader.new(loadRoots(), musicIds())
	task.spawn(pcall, player.RequestStreamAroundAsync, player, camLookAt)
	task.spawn(askIntro)

	-- 3  the counter. It shows the loader's real progress, never ahead of an even
	--    count-up to finishAt, and never going backwards when more of the map
	--    arrives. The loop ends on the clock alone - no callback, thread or asset
	--    can keep it going - and the finished state is then written out explicitly.
	local countFrom = os.clock()
	local finishAt = math.max(started + LOAD_TIME, countFrom + MIN_COUNT_TIME)
	local function show(fraction, total)
		counter.Text = string.format("%s / %s — %d%%", commas(math.floor(fraction * total)), commas(total),
			math.floor(fraction * 100))
	end
	local shown = 0
	while os.clock() < finishAt do
		local x = math.clamp((os.clock() - countFrom) / (finishAt - countFrom), 0, 1)
		local done, total = loader:Progress()
		local real = total > 0 and done / total or 0
		shown = math.max(shown, math.min(real, 1 - (1 - x) ^ 2))
		show(shown, total)
		RunService.Heartbeat:Wait()
	end
	local result = loader:Finish()   -- anything still out is written off here
	local _, total = loader:Progress()
	show(1, total)
	print(string.format("[Loading] %s assets in %.2fs: %d downloads, %d failed, %d still out at the cut-off",
		commas(total), os.clock() - started, result.downloads, result.failed, result.pending))

	if picture ~= "shown" then
		picture = "none"   -- stop waiting for it: a late arrival stays hidden
		bg.Visible = false
		tween(cover, 0.6, { BackgroundTransparency = 1 })   -- no picture: show the live view instead
	end

	-- 4  the fly-down needs the character; with none after NO_CHARACTER_LIMIT seconds the
	--    camera is handed over anyway (never stuck on the opening view)
	--    A late character (the server's first spawn running slow) still gets the fly-down:
	--    the opening view holds until it arrives, up to LATE_CHARACTER_LIMIT, rather than the
	--    camera being dropped where it stands with nobody to follow.
	local waitFrom = os.clock()
	if not waitForRoot(NO_CHARACTER_LIMIT) then
		warn("[Loading] no live character " .. NO_CHARACTER_LIMIT .. "s after loading finished - flying down when it arrives")
		if not waitForRoot(LATE_CHARACTER_LIMIT) then
			abort("no live character " .. (NO_CHARACTER_LIMIT + LATE_CHARACTER_LIMIT) .. "s after loading finished")
			return
		end
		print(string.format("[Loading] character arrived %.1fs after loading finished", os.clock() - waitFrom))
	end
	-- (no "click to continue": straight into the fly-down, or World 1's first-time intro)
	local asked = os.clock()
	while introPlay == nil and os.clock() - asked < INTRO_WAIT do RunService.Heartbeat:Wait() end
	local playIntro = introPlay == true
	introPlay = false   -- a late answer is ignored
	local pulse

	-- 5  the fly-down
	if pulse then pulse:Cancel() end
	catcher.Visible = false
	tween(hint, 0.2, { TextTransparency = 1 })
	tween(status, 0.2, { TextTransparency = 1 })
	tween(counter, 0.2, { TextTransparency = 1 })
	tween(shade, 0.5, { BackgroundTransparency = 1 })
	unblur()   -- the world "finishes loading" into focus as the camera sets off
	if picture == "shown" then
		-- the picture zooms with the camera's first move while it melts away
		cover.BackgroundTransparency = 1
		tween(bg, 0.55, { ImageTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		tween(bg, 0.55, { Size = UDim2.fromScale(1.22, 1.22) }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	end

	local root, hum = waitForRoot()
	local focusEnd, facing = subjectPosition(hum, root), root.CFrame.LookVector
	local startFov = pictureFov(workspace.CurrentCamera)
	local t0 = os.clock()
	unbind(HOLD)
	-- out of the loading GUI, so the wind can still fade after the GUI is gone
	local windOn = false
	if wind then
		wind.Volume = 0
		wind.Parent = game:GetService("SoundService")
	end
	startShake()
	startStreaks()

	local function handOff(eye, focus)
		unbind(FLY)
		local cam = workspace.CurrentCamera
		cam.FieldOfView = baseFov
		cam.CFrame, cam.Focus = CFrame.lookAt(eye, focus), CFrame.new(focus)
		if hum then cam.CameraSubject = hum end
		cam.CameraType = Enum.CameraType.Custom
		release()
		if wind then
			stopStreaks(false)
			TweenService:Create(wind, TweenInfo.new(WIND_FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = 0 }):Play()
			task.delay(WIND_FADE + 0.05, function()
				stopShake()
				stopStreaks(true)
				wind:Destroy()
			end)
		end
		-- Roblox's camera now places itself each frame; ease from the last cinematic
		-- frame into it so any small difference never shows as a jump.
		local from, tb = cam.CFrame, os.clock()
		RunService:BindToRenderStep(BLEND, CAMERA_STEP, function()
			local a = math.min((os.clock() - tb) / BLEND_TIME, 1)
			local c = workspace.CurrentCamera
			if a < 1 and c then
				c.CFrame = from:Lerp(c.CFrame, smooth(0, 1, a))
			else
				unbind(BLEND)
				gui:Destroy()
			end
		end)
	end

	-- first time in World 1: the intro cinematic flies instead, landing on the same spot the
	-- fly-down would, and hands the camera back through handOff
	if playIntro and Intro then
		local ok, err = pcall(Intro.Play, { First = true, HandOff = handOff })
		if not ok then abort(err) end
		return
	end

	RunService:BindToRenderStep(FLY, CAMERA_STEP, function()
		local ok, err = pcall(function()
			local t = math.min((os.clock() - t0) / FLIGHT_TIME, 1)
			local e = (1 - math.cos(math.pi * t)) / 2
			local r, h = liveRoot()
			if r then
				root, hum = r, h
				focusEnd, facing = subjectPosition(h, r), r.CFrame.LookVector
			end
			local eye, focus = flightPose(e, focusEnd, facing)
			local cam = workspace.CurrentCamera
			if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
			cam.CFrame, cam.Focus = CFrame.lookAt(eye, focus), CFrame.new(focus)
			cam.FieldOfView = startFov + (baseFov - startFov) * e + FOV_SWELL * math.sin(math.pi * e)
			-- rushing wind: silent until WIND_FROM, then louder and a touch higher the closer the camera gets
			if wind then
				local w = smooth(WIND_FROM, WIND_FULL, t)
				if w > 0 and not windOn then windOn = true; wind:Play() end
				wind.Volume = windPeak * w ^ 1.6
				wind.PlaybackSpeed = 0.92 + 0.12 * w
			end
			if t >= 1 then handOff(eye, focus) end
		end)
		if not ok then abort(err) end
	end)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then abort(err) end
