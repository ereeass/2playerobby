--=====================================================================
-- Spectate   (TrollUI)
--
-- Watching another duo from behind their scooter, on this player's machine only.
--
-- WHO rides together comes from the server, never from where players stand: the
-- server's ScooterSystem.Spectate reads RideManager and marks every scooter whose duo
-- can be watched with SpectateDriver / SpectateMotor (the riders' UserIds). The marks go
-- the moment the ride finishes, goes down, loses a rider or ends, so the list here is
-- only ever live, complete duos. Scooters are streamed to everyone, so their marks are
-- always here; the list follows them by events, with no scanning.
--
--   Spectate.Start(opts)   begin: the duo furthest along the course, then follows the list
--                          opts.onChanged(duo | nil, index, count): what the bar shows
--                          opts.fade: a Frame for the blink between two duos
--   Spectate.Step(d)       the previous (-1) / next (+1) duo, round the list; false = none
--   Spectate.Stop()        the camera exactly as it was, streaming back, connections gone
--
-- The camera (Scriptable, and only while there is a duo to watch) frames the SCOOTER, not a
-- player: behind it and a little above and to one side, so the rear rider never hides the
-- driver, looking just past its nose. It turns with the scooter's heading only (its tilt
-- and roll are ignored, so bumps, ramps and jumps never shake it), eases round turns and
-- up and down, and a wall between it and the scooter pulls it in. The viewer can turn it
-- all the way round the scooter (right-drag, a finger on the world, the right stick); it
-- keeps following from that angle, and a new duo starts from behind again. With nobody to watch it
-- hands the camera back and the bar says so; the first duo to set off is picked up.
-- Nothing here touches anyone else's camera, controls, role or scooter.
--=====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RS               = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes"):WaitForChild("Spectate")
-- a troll show on the duo being watched (Rocket Launch, Explode Players) has its own camera
-- moves: that troll's clock and moves, the same as the two riders' own screens
local Timelines = require(RS:WaitForChild("TrollFx"):WaitForChild("Timelines"))

local ATTR_DRIVER, ATTR_MOTOR = "SpectateDriver", "SpectateMotor"
local BIND = "TrollSpectateCamera"

-- the chase camera, in studs from the scooter's chassis. Behind it, but far enough to
-- one side and above that the driver shows past the rear rider's shoulder.
local FOCUS_UP  = 3      -- the point it frames: the riders' middles
local BACK      = 12     -- behind it
local UP        = 5.8    -- above that point
local SIDE      = 5      -- to one side
local AHEAD     = 5      -- it looks this far past the scooter's nose
local LOOK_UP   = 0.4
local FOV       = 70
-- a wall on its side: it swings round to the other side, or with both sides walled in
-- (a cliff, a tunnel) rises over the scooter - HIGH_UP higher and HIGH_IN closer
local HIGH_UP, HIGH_IN = 5, 0.35
local PREFER    = 0.2    -- how much freer (share of its distance) another place must be
local CHOOSE_EVERY = 0.15   -- seconds between looking round for the freer place
local TURN      = 4.5    -- rates (1/s): turning with the scooter,
local LIFT      = 7      -- following it up and down,
local SWING     = 2.5    -- moving to another side / height,
local REGROW    = 3      -- and backing out again once a wall is gone
local MIN_DIST  = 4      -- a wall never pulls it closer than this
-- looking round the scooter (all the way round): right-drag with a mouse, a finger
-- dragged across the world on a touch screen, or the right stick
local ORBIT_MOUSE = 0.008   -- radians per pixel dragged
local ORBIT_TOUCH = 0.011
local ORBIT_STICK = 3       -- radians per second, stick all the way over
local STICK_DEAD  = 0.2
-- and up and down, at the same distance (it never zooms): how far above / below the
-- scooter it may go, as an angle from level (radians)
local PITCH_MIN, PITCH_MAX = math.rad(-10), math.rad(80)
-- the tilt kept within those (from the usual angle), so dragging past a limit and back
-- moves it again straight away
local BASE_TILT = math.atan2(UP, math.sqrt(BACK * BACK + SIDE * SIDE))
local function clampPitch(p) return math.clamp(p, PITCH_MIN - BASE_TILT, PITCH_MAX - BASE_TILT) end
local BLINK_OUT, BLINK_IN = 0.12, 0.24

local Spectate = {}

local active, opts = false, nil
local bin                          -- workspace.RideSystem.Scooters
local list, byScooter = {}, {}     -- watchable duos, in the order they were first seen
local seen = 0
local current                      -- the duo the camera is on
local shown                        -- the duo the bar names (ahead of the camera during a blink)
local conns, scooterConns = {}, {}
local blinkToken, blinking = 0, false

---------------------------------------------------------------- the camera
local saved                        -- the camera as it was: { Type, Subject, Fov, CFrame }
local focusPos, yaw, dist
local snap = true
local side, high = 1, 0            -- where it sits now: -1 left .. 1 right; 0 behind .. 1 over
local sideTo, highTo = 1, 0        -- where it is heading
local chooseIn = 0
local orbit = 0                    -- radians the viewer has turned it round the scooter
local pitch = 0                    -- radians the viewer has tilted it up (+) or down (-)
local stickY = 0
local dragMouse, dragTouch = false, nil
local lastMouseX, lastMouseY       -- a pointer that reports no Delta: measured from where it was
local stickX = 0
local showFrom, showT0             -- a troll's show: where the camera was when it began, and when
local showSide, showRoom = 1, 1    -- ...the side of it with room, and how much of the way is clear
local SHOW_BLEND = 0.4             -- seconds from the chase camera into the show's
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- triggers and kill zones never pull it in

local function wrap(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- the scooter's heading on the ground (nil while it points straight up or down)
local function headingOf(cf)
	local look = cf.LookVector
	if look.X * look.X + look.Z * look.Z < 0.02 then return nil end
	return math.atan2(-look.X, -look.Z)
end

-- what the camera looks through: anybody (a rider, a player walking past, a critter)
-- and anything you can't see (invisible walls)
local function seeThrough(part)
	if part.Transparency >= 0.9 then return part end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return model end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- the first real wall between `from` and `from + dir` (nil: none)
local function wallHit(from, dir, skip)
	for _ = 1, 4 do
		rayParams.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(from, dir, rayParams)
		if not hit then return nil end
		local through = seeThrough(hit.Instance)
		if not through then return hit end
		table.insert(skip, through)
	end
	return nil
end

local function follow(dt)
	local cam = workspace.CurrentCamera
	local duo = current
	local scooter = duo and duo.Scooter
	local chassis = scooter and scooter.Parent and scooter.PrimaryPart
	if not (cam and chassis) then return end   -- gone this frame: the list moves on
	dt = math.min(dt, 1 / 20)

	-- A troll show on this duo (TrollFx plays it; the scooter here is where this machine
	-- shows it): the show's camera - behind where it stood, following it (up after a rocket),
	-- shaking with it, then the explosion - blended in from the chase camera, the viewer's
	-- turn round it kept. Afterwards the list moves on to the next duo as always.
	local start, base = scooter:GetAttribute("TrollStart"), scooter:GetAttribute("TrollBase")
	local Show = Timelines.Of(scooter)   -- that troll's clock (the rocket's or the explosion's)
	if Show and type(start) == "number" and typeof(base) == "CFrame" then
		local t = math.max(workspace:GetServerTimeNow() - start, 0)
		if math.abs(stickX) > STICK_DEAD then orbit = wrap(orbit - stickX * ORBIT_STICK * dt) end
		local baseHeading = headingOf(base) or 0
		local turn = wrap((yaw or baseHeading) - baseHeading + orbit)
		-- what it sees through: the scooters, everybody, the show's own pieces
		local skip = { scooter, bin }
		local mine = workspace:FindFirstChild("TrollFxLocal")
		if mine then table.insert(skip, mine) end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(skip, p.Character) end
		end
		if not showFrom then
			showFrom, showT0 = cam.CFrame, os.clock()
			-- the side with room for the whole show (never inside a cliff), keeping the chase
			-- camera's own side when that one has room
			showSide = Show.BestSide(base, table.clone(skip), turn, side >= 0 and 1 or -1)
			showRoom = 1
		end
		local eye, look, fovAdd = Show.Camera(base, chassis.Position + Vector3.new(0, 2, 0), t, turn, showSide)
		-- a wall in the way pulls it in at once; it backs out again gently
		local _, share = Show.Clear(eye, look, skip, MIN_DIST + 1)
		if share < showRoom then showRoom = share else showRoom += (share - showRoom) * (1 - math.exp(-REGROW * dt)) end
		eye = Show.Pulled(eye, look, showRoom)
		local want = CFrame.lookAt(eye, look)
		local s = Show.Shake(t)
		if s > 0 then
			local n = os.clock() * 24
			want = want * CFrame.new(math.noise(n, 3.1) * s * 0.9, math.noise(n, 8.7) * s * 0.9, 0)
				* CFrame.Angles(0, 0, math.noise(n, 5.3) * s * 0.05)
		end
		local k = math.clamp((os.clock() - showT0) / SHOW_BLEND, 0, 1)
		k = k * k * (3 - 2 * k)
		cam.CFrame = showFrom:Lerp(want, k)
		cam.FieldOfView = FOV + fovAdd * k
		local mb = dragMouse and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
		if UserInputService.MouseBehavior ~= mb then UserInputService.MouseBehavior = mb end
		return
	end
	showFrom = nil

	local cf = chassis.CFrame
	local target = cf.Position + Vector3.new(0, FOCUS_UP, 0)
	local heading = headingOf(cf)
	local snapped = snap or not focusPos
	if snapped then
		snap = false
		focusPos, yaw, dist = target, heading or 0, nil
		sideTo, highTo = 1, 0
		orbit, pitch = 0, 0          -- a new duo: from behind again
	else
		-- along the ground it stays right on the scooter; up and down it eases (bumps, jumps)
		local ay = 1 - math.exp(-LIFT * dt)
		focusPos = Vector3.new(target.X, focusPos.Y + (target.Y - focusPos.Y) * ay, target.Z)
		if heading then yaw += wrap(heading - yaw) * (1 - math.exp(-TURN * dt)) end
	end

	-- the viewer turning it round (the right stick keeps turning while held)
	if math.abs(stickX) > STICK_DEAD then orbit = wrap(orbit - stickX * ORBIT_STICK * dt) end
	if math.abs(stickY) > STICK_DEAD then pitch = clampPitch(pitch - stickY * ORBIT_STICK * 0.6 * dt) end
	local view  = yaw + orbit
	local fwd   = Vector3.new(-math.sin(view), 0, -math.cos(view))
	local right = Vector3.new(math.cos(view), 0, -math.sin(view))
	local function offset(s, h)
		local v = -fwd * (BACK * (1 - HIGH_IN * h)) + right * (SIDE * s * (1 - h)) + Vector3.new(0, UP + HIGH_UP * h, 0)
		-- tilted up or down by the viewer, the same distance from the scooter
		local flat = Vector3.new(v.X, 0, v.Z)
		local len = v.Magnitude
		local e = math.clamp(math.atan2(v.Y, flat.Magnitude) + pitch, PITCH_MIN, PITCH_MAX)
		return flat.Unit * (len * math.cos(e)) + Vector3.new(0, len * math.sin(e), 0)
	end

	-- walls (never a scooter or anybody) between the scooter and the camera
	local skip = { scooter, bin }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(skip, p.Character) end
	end
	local function freeShare(v)   -- 0..1: how much of the way to `v` is clear
		local hit = wallHit(focusPos, v, table.clone(skip))
		return hit and (hit.Position - focusPos).Magnitude / v.Magnitude or 1
	end

	-- now and then: is its own side walled in, and somewhere else freer? Behind on its own
	-- side is where it belongs whenever that is clear; the place it is heading for is kept
	-- unless another is clearly freer (PREFER); rising over the top is the last resort.
	chooseIn -= dt
	if chooseIn <= 0 or snapped then
		chooseIn = CHOOSE_EVERY
		local own = freeShare(offset(sideTo, 0))
		if own >= 0.98 then
			highTo = 0
		else
			local best, bestScore
			for _, place in ipairs({ { sideTo, 0, own }, { -sideTo, 0 }, { sideTo, 1 } }) do
				local s, h = place[1], place[2]
				local score = (place[3] or freeShare(offset(s, h)))
					+ ((s == sideTo and h == highTo) and PREFER or 0)
					- (h == 1 and 0.3 or 0)
				if not bestScore or score > bestScore then best, bestScore = place, score end
			end
			sideTo, highTo = best[1], best[2]
		end
	end
	if snapped then
		side, high = sideTo, highTo
	else
		local k = 1 - math.exp(-SWING * dt)
		side += (sideTo - side) * k
		high += (highTo - high) * k
	end

	-- and whatever wall is left pulls it in
	local want = offset(side, high)
	local full = want.Magnitude
	local hit = wallHit(focusPos, want, skip)
	local allowed = hit and math.max((hit.Position - focusPos).Magnitude - 0.8, MIN_DIST) or full
	if not dist or allowed < dist then
		dist = allowed
	else
		dist += (allowed - dist) * (1 - math.exp(-REGROW * dt))
	end

	local eye = focusPos + want.Unit * dist
	cam.CFrame = CFrame.lookAt(eye, focusPos + fwd * AHEAD + Vector3.new(0, LOOK_UP, 0))
	cam.FieldOfView = FOV
	-- a free pointer for the bar's buttons (whatever Shift-lock was doing), held still
	-- while the right button drags the view round
	local mb = dragMouse and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
	if UserInputService.MouseBehavior ~= mb then UserInputService.MouseBehavior = mb end
end

local function holdCamera()
	snap = true
	if saved then return end
	local cam = workspace.CurrentCamera
	saved = { Type = cam.CameraType, Subject = cam.CameraSubject, Fov = cam.FieldOfView, CFrame = cam.CFrame }
	cam.CameraType = Enum.CameraType.Scriptable
	-- after Roblox's own camera, so nothing else moves it this frame
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, follow)
end

-- back exactly as it was, on the player's own character
local function releaseCamera()
	if not saved then return end
	RunService:UnbindFromRenderStep(BIND)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default   -- never left held by a drag
	local s = saved
	saved, focusPos, dist, showFrom = nil, nil, nil, nil
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam.FieldOfView = s.Fov
	cam.CFrame = s.CFrame
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	cam.CameraSubject = hum or s.Subject
	cam.CameraType = (s.Type ~= Enum.CameraType.Scriptable) and s.Type or Enum.CameraType.Custom
end

---------------------------------------------------------------- the duos
local function notify()
	if not (opts and opts.onChanged) then return end
	opts.onChanged(shown, shown and table.find(list, shown) or 0, #list)
end

-- how far along the course the duo is (CourseProgress, from the server)
local function progressOf(duo)
	local best = 0
	for _, id in ipairs({ duo.DriverId, duo.MotorId }) do
		local p = Players:GetPlayerByUserId(id)
		local v = p and p:GetAttribute("CourseProgress")
		if type(v) == "number" and v > best then best = v end
	end
	return best
end

local function furthest()
	local pick, far = nil, -1
	for _, duo in ipairs(list) do
		local p = progressOf(duo)
		if p > far then pick, far = duo, p end
	end
	return pick
end

-- the camera goes to `duo` (nil: nobody to watch - it is handed back)
local function aim(duo)
	current = duo
	if duo then
		holdCamera()
		remote:FireServer(duo.Scooter)   -- streaming round it (the road it is on)
	else
		releaseCamera()
		remote:FireServer(nil)
	end
end

local function setFade(t)
	local fade = opts and opts.fade
	if not fade then return end
	fade.Visible = t < 1
	fade.BackgroundTransparency = t
end

local function blinkTo(fade, t, dur)
	TweenService:Create(fade, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = t }):Play()
end

-- The bar names the new duo at once. From nobody, or to nobody, the camera goes straight
-- there; from one duo to another the world blinks to black and back, so it never flies
-- across the map. Clicking again mid-blink just changes where it lands.
local function switchTo(duo)
	shown = duo
	notify()
	local fade = opts and opts.fade
	if not current or not duo or not fade then
		blinkToken += 1
		blinking = false
		setFade(1)
		aim(duo)
		return
	end
	if blinking or duo == current then return end   -- mid-blink: it lands on `shown`
	blinking = true
	blinkToken += 1
	local token = blinkToken
	fade.Visible = true
	blinkTo(fade, 0, BLINK_OUT)
	task.delay(BLINK_OUT, function()
		if not active or token ~= blinkToken then return end
		aim(shown)
		blinking = false
		blinkTo(fade, 1, BLINK_IN)
		task.delay(BLINK_IN, function()
			if token == blinkToken and not blinking then fade.Visible = false end
		end)
	end)
end

-- after the list changed: a duo that went is replaced by the one after it, and with
-- nobody on screen the one furthest along is picked up
local function settle()
	if not active then return end
	if shown and not byScooter[shown.Scooter] then
		local i = math.clamp(shown.Gone or 1, 1, math.max(#list, 1))
		switchTo(list[i])
	elseif not shown and #list > 0 then
		switchTo(furthest())
	else
		notify()   -- the count changed
	end
end

local function consider(scooter)
	local d, m = scooter:GetAttribute(ATTR_DRIVER), scooter:GetAttribute(ATTR_MOTOR)
	local ok = type(d) == "number" and type(m) == "number" and scooter.Parent == bin
	local duo = byScooter[scooter]
	if ok and not duo then
		seen += 1
		duo = { Scooter = scooter, DriverId = d, MotorId = m, Seen = seen }
		byScooter[scooter] = duo
		table.insert(list, duo)
	elseif ok then
		duo.DriverId, duo.MotorId = d, m
	elseif duo then
		byScooter[scooter] = nil
		local i = table.find(list, duo)
		if i then table.remove(list, i) end
		duo.Gone = i or 1   -- the one after it now stands here
	end
end

local function watch(scooter)
	if scooterConns[scooter] then return end
	local function changed() consider(scooter); settle() end
	scooterConns[scooter] = {
		scooter:GetAttributeChangedSignal(ATTR_DRIVER):Connect(changed),
		scooter:GetAttributeChangedSignal(ATTR_MOTOR):Connect(changed),
	}
	consider(scooter)
end

local function unwatch(scooter)
	local c = scooterConns[scooter]
	if c then
		for _, conn in ipairs(c) do conn:Disconnect() end
		scooterConns[scooter] = nil
	end
	consider(scooter)
end

---------------------------------------------------------------- api
function Spectate.Start(o)
	if active then return end
	active, opts = true, o
	setFade(1)
	local sys = workspace:FindFirstChild("RideSystem")
	bin = sys and sys:FindFirstChild("Scooters")
	if bin then
		for _, scooter in ipairs(bin:GetChildren()) do watch(scooter) end
		table.insert(conns, bin.ChildAdded:Connect(function(s) watch(s); settle() end))
		table.insert(conns, bin.ChildRemoved:Connect(function(s) unwatch(s); settle() end))
	end
	settle()
	if not shown then notify() end   -- nobody riding: the bar says so

	-- looking round: right-drag, a finger on the world (not on a button), the right stick
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragMouse = true
			lastMouseX, lastMouseY = input.Position.X, input.Position.Y
		elseif input.UserInputType == Enum.UserInputType.Touch and not dragTouch then
			dragTouch = input
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement and dragMouse then
			local dx = input.Delta.X
			if dx == 0 and lastMouseX then dx = input.Position.X - lastMouseX end
			local dy = input.Delta.Y
			if dy == 0 and lastMouseY then dy = input.Position.Y - lastMouseY end
			lastMouseX, lastMouseY = input.Position.X, input.Position.Y
			orbit = wrap(orbit - dx * ORBIT_MOUSE)
			pitch = clampPitch(pitch + dy * ORBIT_MOUSE)
		elseif kind == Enum.UserInputType.Touch and input == dragTouch then
			orbit = wrap(orbit - input.Delta.X * ORBIT_TOUCH)
			pitch = clampPitch(pitch + input.Delta.Y * ORBIT_TOUCH)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stickX, stickY = input.Position.X, input.Position.Y
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragMouse = false
		elseif input == dragTouch then
			dragTouch = nil
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stickX, stickY = 0, 0
		end
	end))
end

function Spectate.Step(d)
	if not active or #list < 2 then return false end
	local i = table.find(list, shown) or 1
	switchTo(list[(i - 1 + d) % #list + 1])
	return true
end

function Spectate.Stop()
	if not active then return end
	active = false
	for _, c in ipairs(conns) do c:Disconnect() end
	table.clear(conns)
	dragMouse, dragTouch, stickX, stickY, orbit, pitch = false, nil, 0, 0, 0, 0
	for scooter, c in pairs(scooterConns) do
		for _, conn in ipairs(c) do conn:Disconnect() end
	end
	table.clear(scooterConns)
	table.clear(list)
	table.clear(byScooter)
	blinkToken += 1
	blinking = false
	setFade(1)
	shown = nil
	current = nil
	releaseCamera()
	remote:FireServer(nil)
	opts, bin = nil, nil
end

function Spectate.IsActive()
	return active
end

-- the duo the camera is on right now (not mid-blink), or nil
function Spectate.Current()
	if not active or blinking then return nil end
	return current
end

return Spectate
