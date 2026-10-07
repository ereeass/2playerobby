--=====================================================================
-- FinishCutscene   (StarterPlayerScripts)
--
-- The finish-line victory cinematic, on THIS player's machine only: nobody else's
-- camera, controls or game is touched. Other players just see this scooter brake to a
-- stop past the line for a few seconds.
--
--   The finish  FinishLine: this player's scooter crossing a gate tagged
--               Config.FinishTag (Workspace["Finish Area"].FinishGate) from its road
--               side. Each ride gets its cutscene once; the next ride gets it again.
--   Before      everything the scene needs is taken the moment they cross, while it is
--               all still there: who rides the scooter and as what (straight from
--               RiderAttach's welds and the Role it gave them), that scooter and those
--               avatars copied (Scene), and the road they came in on (Path).
--   Then        the controls stand down (Lock: the scooter brakes to a stop and holds;
--               no key, pedal, stick or touch reaches the scooter, the character or the
--               camera) and the screen fades to black (Fade). There the real scooter and
--               riders are hidden on this machine, the HUD put away and the camera
--               taken (CameraRig).
--   The scene   Config.Duration seconds: the copy rolls in from behind the line at a
--               slow, cinematic pace, the driver throws their arms up (Celebration), the
--               camera swings from behind the riders round to the front as they cross,
--               and confetti (Confetti) falls round them and bursts at the line.
--   After       fade to black, everything back exactly as it was - camera, controls,
--               HUD, the real ride - and the game fades back in.
--
-- Everything taken is handed to a session that gives it all back, in reverse, even if a
-- step fails, the ride goes into the water mid-way (DeathState: the cutscene stops at
-- once and the death popup takes over) or it somehow never ends (Config.Watchdog).
--=====================================================================

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService         = game:GetService("SoundService")
local RS                   = game:GetService("ReplicatedStorage")

local Config      = require(script:WaitForChild("Config"))
local FinishLine  = require(script:WaitForChild("FinishLine"))
local Path        = require(script:WaitForChild("Path"))
local Scene       = require(script:WaitForChild("Scene"))
local Celebration = require(script:WaitForChild("Celebration"))
local CameraRig   = require(script:WaitForChild("CameraRig"))
local Confetti    = require(script:WaitForChild("Confetti"))
local Fade        = require(script:WaitForChild("Fade"))
local Lock        = require(script:WaitForChild("Lock"))

local Root      = RS:WaitForChild("ScooterSystem")
local Remotes   = Root:WaitForChild("Remotes")
local Cinematic = require(Root:WaitForChild("Cinematic"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STEP       = "FinishCutsceneScene"    -- the scene's per-frame update (BindToRenderStep)
local DEATH_HOLD = "DeathCameraNoControls"  -- DeathClient's camera hold (StarterGui.DeathGui)
local COOLDOWN   = 2                        -- seconds after a cutscene before another may start

local function log(...)
	if Config.Debug then print("[FinishCutscene]", ...) end
end

---------------------------------------------------------------- session
-- Everything a cutscene changes registers how to put it back. Each is put back once, in
-- reverse order, whatever happens. Restore() puts back all but the ones marked `last`
-- (the fade: the game fades back in once everything else is back); Finish() the rest.
local Session = {}
Session.__index = Session

function Session.new()
	return setmetatable({ tasks = {}, alive = true }, Session)
end

function Session:Add(name, fn, last)
	table.insert(self.tasks, { name = name, fn = fn, last = last == true, done = false })
end

function Session:_run(entry)
	if entry.done then return end
	entry.done = true
	local ok, err = pcall(entry.fn)
	if not ok then warn("[FinishCutscene] putting back '" .. entry.name .. "' failed: " .. tostring(err)) end
end

function Session:Restore()
	for i = #self.tasks, 1, -1 do
		if not self.tasks[i].last then self:_run(self.tasks[i]) end
	end
end

function Session:Finish()
	self.alive = false
	for i = #self.tasks, 1, -1 do self:_run(self.tasks[i]) end
end

-- waits, and says whether the cutscene is still on
function Session:Wait(seconds)
	local stop = os.clock() + seconds
	while self.alive and os.clock() < stop do task.wait() end
	return self.alive
end

---------------------------------------------------------------- the drive
-- How far the scene's scooter has rolled by time t (Config.Speed: studs/s at times,
-- straight lines between), its speed then, when it reaches the line, and how far it goes.
local function driveProfile()
	local keys = Config.Speed
	local function speedAt(t)
		if t <= keys[1][1] then return keys[1][2] end
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if t <= b[1] then return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1]) end
		end
		return keys[#keys][2]
	end
	local dt = 1 / 240
	local n = math.ceil(Config.Duration / dt)
	local dist, s = { 0 }, 0
	for i = 1, n do
		local t = (i - 1) * dt
		s += (speedAt(t) + speedAt(t + dt)) / 2 * dt
		dist[i + 1] = s
	end
	local function distanceAt(t)
		local f = math.clamp(t / dt, 0, n)
		local i = math.floor(f)
		local a, b = dist[i + 1], dist[math.min(i + 2, n + 1)]
		return a + (b - a) * (f - i)
	end
	local crossAt = Config.Duration
	for i = 1, n + 1 do
		if dist[i] >= Config.StartBehind then crossAt = (i - 1) * dt break end
	end
	return distanceAt, speedAt, crossAt, dist[n + 1]
end
local distanceAt, speedAt, CROSS_AT, TOTAL = driveProfile()

---------------------------------------------------------------- the ride
local ROLE_ORDER = { Driver = 1, Passenger = 2 }

-- the chassis this player stands on (RiderAttach's weld), while alive
local function myChassis()
	local ch   = player.Character
	local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	if not (hum and hum.Health > 0 and weld and weld.Part0) then return nil end
	return weld.Part0
end

-- Who rides this chassis, and as what: every character RiderAttach has welded to it,
-- with the Role it gave them (anything unexpected counts as neither). Driver first.
local function captureRide(chassis)
	local scooter = chassis and chassis.Parent
	if not (scooter and scooter:IsA("Model") and scooter.Parent) then return nil end
	local riders, seen = {}, {}
	local function add(weld)
		local root = weld.Part1
		local char = root and root.Parent
		if weld.Part0 ~= chassis or not char or seen[char] then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		seen[char] = true
		local role = weld:GetAttribute("Role")
		table.insert(riders, {
			Character = char, Humanoid = hum, Root = root, Weld = weld,
			Player = Players:GetPlayerFromCharacter(char),
			Role = (role == "Driver" or role == "Passenger") and role or "Rider",
		})
	end
	for _, joint in ipairs(chassis:GetJoints()) do
		if joint:IsA("Weld") and joint.Name == "ScooterRiderWeld" then add(joint) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do   -- anyone the joints didn't list
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local weld = root and root:FindFirstChild("ScooterRiderWeld")
		if weld and weld:IsA("Weld") then add(weld) end
	end
	table.sort(riders, function(a, b) return (ROLE_ORDER[a.Role] or 3) < (ROLE_ORDER[b.Role] or 3) end)
	return { Scooter = scooter, Chassis = chassis, Riders = riders }
end

---------------------------------------------------------------- sound
-- one of Config.Sounds, on this machine only; it goes once it has played
local function playSound(spec)
	if type(spec) ~= "table" or type(spec.Id) ~= "string" or spec.Id == "" or (spec.Volume or 0) <= 0 then return end
	local s = Instance.new("Sound")
	s.Name = "FinishCutsceneSound"
	s.SoundId = spec.Id
	s.Volume = spec.Volume
	s:SetAttribute("AudioCategory", "SFX")   -- the SFX volume slider (SettingsController)
	s.Parent = SoundService
	s.Ended:Once(function() s:Destroy() end)
	task.delay(15, function() if s.Parent then s:Destroy() end end)
	s:Play()
end

---------------------------------------------------------------- the cutscene
local function run(session, crossing)
	------------------------------------------------ 1. the ride, as it is right now
	local ride = captureRide(crossing.Chassis)
	if not ride then return end
	local mine, driver
	for _, r in ipairs(ride.Riders) do
		if r.Player == player then mine = r end
		if r.Role == "Driver" and not driver then driver = r end
	end
	if not mine then return end

	-- the copy, made now: whatever happens to the real scooter or its riders from here on
	-- (the ride ending, a rider leaving) the scene keeps what was there
	local scene, why = Scene.Build(ride)
	if not scene then
		warn("[FinishCutscene] no cutscene: " .. tostring(why))
		return
	end
	session:Add("remove the cinematic", function() scene:Destroy() end)

	-- ground rays and the camera's line of sight look past every scooter and every character
	local ignore = { scene.Model }
	for _, r in ipairs(scene.Riders) do table.insert(ignore, r.Model) end
	for _, r in ipairs(ride.Riders) do table.insert(ignore, r.Character) end
	local bin = workspace:FindFirstChild("RideSystem")
	if bin then table.insert(ignore, bin) end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	local path = Path.Build(crossing, Config.StartBehind, TOTAL - Config.StartBehind + 4, Config.LaneClamp, ignore)
	local s0 = path.Cross - Config.StartBehind
	log(("crossed %.1f studs off centre; %d rider(s); road %.1f studs, line at %.1f, line reached at %.2f s")
		:format(crossing.Lateral, #scene.Riders, path.Length, path.Cross, CROSS_AT))

	------------------------------------------------ 2. the controls stand down; fade out
	Lock.Controls(session)
	local fade = Fade.new(playerGui, Config.Letterbox)
	session:Add("remove the fade", function() fade:Destroy() end, true)   -- last: the game fades back in first
	fade:To(1, Config.FadeOut)
	if not session:Wait(Config.FadeOut) then return end

	------------------------------------------------ 3. at black: the scene takes over
	Lock.Hud(session, playerGui, fade.Gui, Config.HideCoreGui)
	Lock.Ride(session, ride)
	scene:Show()
	scene:Place(path:At(s0), 0, 0)
	table.insert(ignore, scene.Folder)

	local function levelFrame(cf)
		local flat = cf.LookVector * Vector3.new(1, 0, 1)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		return CFrame.lookAt(cf.Position, cf.Position + flat)
	end
	local camera = CameraRig.new(Config, ignore)
	camera:ChooseSide(function(t) return levelFrame(path:At(s0 + distanceAt(t))) end)
	camera:Take()
	session:Add("give the camera back", function() camera:Restore() end)

	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = ignore
	groundParams.RespectCanCollide = true
	groundParams.IgnoreWater = true
	-- the extras never stop the scene: one that can't be set up (or fails later) is left out
	local okConfetti, confetti = pcall(Confetti.new, scene.Folder, Config.Confetti, groundParams)
	if not okConfetti then
		warn("[FinishCutscene] no confetti: " .. tostring(confetti))
		confetti = nil
	end
	local okCheer, celebration = pcall(Celebration.new, scene, Config, CROSS_AT, (driver or mine).Character)
	if okCheer then
		session:Add("stop the celebration", function() celebration:Destroy() end)
	else
		warn("[FinishCutscene] no celebration: " .. tostring(celebration))
		celebration = nil
	end
	local function extra(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then warn("[FinishCutscene] " .. name .. " stopped: " .. tostring(err)) end
		return ok
	end

	------------------------------------------------ the scene, frame by frame
	local cc = Config.Confetti
	local t, look, steer, shower, crossed = 0, nil, 0, 0, false
	local later = {}   -- { at, fn }: the confetti waves at the line

	local function atTheLine(frame)
		local gate = crossing.GateCF
		local aim = frame.Position + Vector3.new(0, 3, 0)
		if confetti then
			for wave, share in ipairs({ 1, 0.6, 0.35 }) do
				table.insert(later, { at = t + (wave - 1) * 0.09, fn = function()
					local n = math.max(1, math.round(cc.Burst * share))
					confetti:Spray(gate * Vector3.new(-cc.ArchHalfWidth, cc.ArchHeight, -1), aim, n)
					confetti:Spray(gate * Vector3.new(cc.ArchHalfWidth, cc.ArchHeight, -1), aim, n)
				end })
			end
			confetti:Pop(frame * Vector3.new(0, 6.5, 0), cc.BurstTop)
		end
		playSound(Config.Sounds.Pop)
		playSound(Config.Sounds.Cheer)
	end

	local function step(dt)
		t += dt
		local d = distanceAt(t)
		local s = s0 + d
		local cf = path:At(s)
		-- the fork follows the bend of the road, gently
		local want = math.clamp(-math.atan(path:Bend(s) * scene.Wheelbase), -0.25, 0.25)
		steer += (want - steer) * (1 - math.exp(-6 * dt))
		scene:Place(cf, d, steer)
		scene:Update(dt, speedAt(t))
		if celebration and not extra("the celebration", celebration.Update, celebration, t) then celebration = nil end

		-- the camera's frame: level, its heading eased so a wobble never shakes the shot
		local flat = cf.LookVector * Vector3.new(1, 0, 1)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		look = look and look:Lerp(flat, 1 - math.exp(-5 * dt)).Unit or flat
		local frame = CFrame.lookAt(cf.Position, cf.Position + look)

		-- confetti: a shower round the riders, thicker once they cross, and the bursts at the line
		local rate = 0
		if t >= cc.ShowerFrom then
			rate = (t < CROSS_AT and cc.Rate) or (t < CROSS_AT + cc.AfterFor and cc.RateAfter) or cc.RateEnd
		end
		shower += rate * dt
		if shower >= 1 then
			local n = math.floor(shower)
			shower -= n
			if confetti and not extra("the confetti", confetti.Shower, confetti, frame, n) then confetti = nil end
		end
		if not crossed and t >= CROSS_AT then
			crossed = true
			extra("the finish-line moment", atTheLine, frame)
		end
		for i = #later, 1, -1 do
			if t >= later[i].at then
				local fn = table.remove(later, i).fn
				if confetti and not extra("the confetti", fn) then confetti = nil end
			end
		end
		if confetti and not extra("the confetti", confetti.Step, confetti, dt) then confetti = nil end
		camera:Shot(t, frame, dt, CROSS_AT)
	end

	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Last.Value, function(dt)
		if not session.alive then return end
		local ok, err = pcall(step, math.min(dt, 1 / 20))
		if not ok then
			warn("[FinishCutscene] the scene failed: " .. tostring(err))
			session:Finish()   -- never leave anyone stuck in a broken scene
		end
	end)
	session:Add("stop the scene", function() RunService:UnbindFromRenderStep(STEP) end)

	fade:To(0, Config.FadeIn)
	fade:Bars(true, 0.5)

	------------------------------------------------ 4. the end: fade out, everything back, fade in
	local endAt = Config.Duration - Config.EndFadeOut
	while session.alive and t < endAt do task.wait() end
	if not session.alive then return end
	fade:To(1, Config.EndFadeOut)
	fade:Bars(false, Config.EndFadeOut)
	if not session:Wait(Config.EndFadeOut) then return end

	session:Restore()
	log("back to the game")
	fade:To(0, Config.ReturnFadeIn)
	session:Wait(Config.ReturnFadeIn)
end

local current                                        -- the session of the cutscene playing, if any
local lastEnded = -math.huge
local done = setmetatable({}, { __mode = "k" })     -- [scooter] = true: that ride has had its cutscene
local down = false                                   -- this player's ride is in the water (DeathState)

local function play(crossing)
	local session = Session.new()
	current = session
	local watchdog = task.delay(Config.Watchdog, function()
		if session.alive then
			warn("[FinishCutscene] the cutscene ran too long; putting everything back")
			session:Finish()
		end
	end)
	local ok, err = xpcall(run, debug.traceback, session, crossing)
	if not ok then warn("[FinishCutscene] " .. tostring(err)) end
	session:Finish()
	pcall(task.cancel, watchdog)
	if current == session then current = nil end
	lastEnded = os.clock()
end

-- Only from normal play: not over another cutscene, the loading screen or the death
-- popup (they have the camera), and never while the ride is down.
local function canStart()
	if current or Cinematic.IsActive() or down then return false end
	if os.clock() - lastEnded < COOLDOWN then return false end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType == Enum.CameraType.Scriptable then return false end
	if next(ContextActionService:GetBoundActionInfo(DEATH_HOLD)) ~= nil then return false end
	return true
end

---------------------------------------------------------------- the finish line
RunService.Heartbeat:Connect(function()
	local chassis = myChassis()
	local crossing = FinishLine.Step(chassis)
	if not crossing then return end
	local scooter = chassis.Parent
	if done[scooter] then return end              -- this ride has had its cutscene
	if not canStart() then
		log("crossed the line, but the camera is busy: no cutscene")
		return
	end
	done[scooter] = true
	task.spawn(play, crossing)
end)

-- The ride went into the water (DeathManager): the death popup takes over at once.
Remotes:WaitForChild("DeathState").OnClientEvent:Connect(function(s)
	down = type(s) == "table" and s.Active == true
	if down and current then
		log("the ride went down: stopping the cutscene")
		current:Finish()
	end
end)
Remotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(state)
	if type(state) ~= "table" or state.Phase ~= "Riding" then down = false end
end)
