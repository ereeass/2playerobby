-- Owns ACTIVE RIDES. Queuing (capsules) and riding (scooter) are separate states;
-- this module only handles riding.
--
-- Every ride is self-contained: its own scooter, controller, rider handles, steer
-- and throttle. Nothing is keyed by anything but the ride itself, so one team can
-- never drive another team's scooter.
--
-- Movement goes through ScooterController, which is the single authority. Nothing
-- here touches a motor or servo directly.

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService    = game:GetService("RunService")
local RS            = game:GetService("ReplicatedStorage")

local Root    = RS:WaitForChild("ScooterSystem")
local Remotes = Root:WaitForChild("Remotes")
local Config  = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local Balance = require(Root:WaitForChild("Shared"):WaitForChild("Balance"))

local ScooterController = require(script.Parent:WaitForChild("ScooterController"))
local RiderAttach       = require(script.Parent:WaitForChild("RiderAttach"))
local RiderPose         = require(script.Parent:WaitForChild("RiderPose"))
local CollisionGroups   = require(script.Parent:WaitForChild("CollisionGroups"))
local StartManager      = require(script.Parent:WaitForChild("StartManager"))
local ScooterSelection  = require(script.Parent:WaitForChild("ScooterSelection"))

-- Analytics only (ScooterSystem.Funnels): funnel(...) reports what already happened, in its
-- own protected thread, so it can never change or hold up anything here.
local function funnel(name, ...)
	local args = table.pack(...)
	task.spawn(function()
		local ok, F = pcall(require, script.Parent:FindFirstChild("Funnels"))
		if ok and type(F) == "table" and type(F[name]) == "function" then
			pcall(F[name], table.unpack(args, 1, args.n))
		end
	end)
end

local LEFT_NOTICE = "Your friend has left the game."

local RideManager = {}
RideManager.Rides      = {}   -- [scooter] = ride
RideManager.PlayerRide = {}   -- [player]  = ride
-- [player] = true while a revive gives them a new character (Relaunch): Main leaves the
-- ride alone when that character arrives
RideManager.Reviving   = {}
-- (scooter) a revive put this ride back on a new scooter somewhere else (Relaunch). A
-- BindableEvent hands a table over as a copy, so it names the scooter: Rides gives the ride.
local relaunched = Instance.new("BindableEvent")
RideManager.Relaunched = relaunched.Event

local function log(...) if Config.DebugLogging then print("[Scooter]", ...) end end

---------------------------------------------------------------- teleport fx
-- Every client draws a poof of mist round each rider in their booth
-- (StarterPlayerScripts.TeleportFx). It builds for TELEPORT_LEAD seconds and
-- bursts as they are moved, so they vanish from the booth inside it. Purely
-- visual: a missing remote never holds a ride up.
local TELEPORT_LEAD = 0.45

local function boothPoof(...)
	local remote = Remotes:FindFirstChild("TeleportFx")
	if not remote then return end
	local positions = {}
	for i = 1, select("#", ...) do
		local p = select(i, ...)
		if typeof(p) == "Vector3" then table.insert(positions, p) end
	end
	if #positions > 0 then remote:FireAllClients(positions, TELEPORT_LEAD) end
end

local function rootPosition(plr)
	local ch  = plr and plr.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position
end

---------------------------------------------------------------- brake
-- The screech and wheel sparks (StarterPlayerScripts.ScooterFx, from the scooter's
-- Braking attribute) follow the BRAKE itself and nothing else: the passenger's
-- controls send whether it is held (DriveInput { Brake = true | false }: Space on a
-- keyboard, the Brake pedal on a touch screen) - its own signal, apart from the
-- throttle. W and S never count, whatever the scooter is doing (the Brake pedal also
-- works as reverse, but it is its own input, not S). The brake held is all that
-- starts it; it stays quiet only while there is nothing to brake: the scooter
-- standing still, the pedal backing it up once it has stopped, or the ride down.
-- Feedback only: the controller brakes exactly as before.
local BRAKE_ON_SPEED, BRAKE_OFF_SPEED = 3, 1.5   -- studs/s along its nose (off lower, so it never flickers)

local function updateBraking(ride)
	local c, scooter = ride.Controller, ride.Scooter
	if not (c.Root and scooter.Parent) then return end
	local was = scooter:GetAttribute("Braking") == true
	-- a ride that is down takes no input (ApplyInput), so a brake let go now would
	-- never arrive: forget it, rather than screech again if the ride carries on
	if ride.Down then ride.BrakeHeld = false end
	local on = false
	if ride.BrakeHeld then
		local v = c.Root.AssemblyLinearVelocity:Dot(c.Root.CFrame.LookVector)   -- + rolling forward, - back
		local need = was and BRAKE_OFF_SPEED or BRAKE_ON_SPEED
		if c.Mode == "brake" then
			on = math.abs(v) > need   -- Space: stops it whichever way it rolls
		else
			on = v > need             -- the Brake pedal: slows a forward roll (then it is reverse)
		end
	end
	if on ~= was then scooter:SetAttribute("Braking", on) end
end

---------------------------------------------------------------- stepper
-- ONE Heartbeat for the whole game that ramps every active ride's throttle.
-- It disconnects itself when the last ride ends.
local stepConn
local function ensureStepper()
	if stepConn then return end
	stepConn = RunService.Heartbeat:Connect(function(dt)
		local any = false
		for _, ride in pairs(RideManager.Rides) do
			if not ride._ended and ride.Controller then
				ride.Controller:Step(dt)
				updateBraking(ride)
				any = true
			end
		end
		if not any and stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
	end)
end

---------------------------------------------------------------- horn
-- Either rider may sound the scooter's horn (Remotes.DriveInput { Horn = true | false },
-- true while held). The server only records WHO is honking, as the HornDriver /
-- HornPassenger attributes on the scooter; every client plays the horn itself, from
-- the scooter (ReplicatedStorage.ScooterSystem.Horn), so nearby players hear it and
-- it goes when the scooter does.
local function setHorn(ride, role, on)
	local scooter = ride.Scooter
	if not (role and scooter and scooter.Parent) then return end
	local attr = "Horn" .. role
	if scooter:GetAttribute(attr) ~= on then scooter:SetAttribute(attr, on) end
end

-- nobody on this ride is honking any more (DeathManager, when it goes into the water)
function RideManager.SilenceHorn(ride)
	if not ride then return end
	setHorn(ride, "Driver", false)
	setHorn(ride, "Passenger", false)
end

---------------------------------------------------------------- lifecycle
-- A scooter of this model, standing at `cf` (its chassis), unanchored, in RideSystem.Scooters.
local function buildScooter(tpl, bin, stationId, cf)
	local scooter = tpl:Clone()
	scooter.Name = "Scooter_Station" .. tostring(stationId)
	-- no avatar may ever collide with it; see CollisionGroups
	CollisionGroups.TagScooter(scooter)
	-- keeps it from tipping sideways while its pitch follows slopes; see Shared.Balance
	Balance.AddRollLock(scooter)
	scooter.Parent = bin
	scooter:PivotTo(cf)
	for _, p in ipairs(scooter:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	return scooter
end

-- Both riders onto the ride's scooter: held, posed, simulated by the driver, and the horn
-- let go when either dies.
local function board(ride)
	local scooter, driver, passenger = ride.Scooter, ride.Driver, ride.Passenger
	local dh, derr = RiderAttach.Attach(scooter, driver, "Driver")
	local ph, perr = RiderAttach.Attach(scooter, passenger, "Passenger")
	if not dh then warn("[Scooter] driver attach failed: " .. tostring(derr)) end
	if not ph then warn("[Scooter] passenger attach failed: " .. tostring(perr)) end
	ride.Riders.Driver, ride.Riders.Passenger = dh, ph

	-- Pose once both are on board: the rear rider's hands rest on the driver's body.
	if dh then RiderPose.Apply(dh, nil) end
	if ph then RiderPose.Apply(ph, dh) end

	-- The driver's machine already simulates the scooter; give it the rear rider too,
	-- so the whole mechanism comes from one place and nobody trails behind it.
	if driver and ph then RiderAttach.SetSimulationOwner(ph, driver) end

	-- a rider who dies (a reset, the water) lets go of the horn
	for role, h in pairs(ride.Riders) do
		table.insert(ride.Conns, h.Humanoid.Died:Connect(function() setHorn(ride, role, false) end))
	end
end

-- A rider still in the game and alive who did not end up held on the scooter (board):
-- they'd be left standing where they were while the ride went on without them.
local function missingRider(ride)
	for role, plr in pairs({ Driver = ride.Driver, Passenger = ride.Passenger }) do
		local hum = plr and plr.Parent and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not ride.Riders[role] then return plr, role end
	end
	return nil
end

-- `stillBoarding` (optional): asked once more just before the riders are moved;
-- false calls the ride off (see below).
function RideManager.Begin(stationId, driver, passenger, checkpointId, spawnPart, stillBoarding)
	-- the DRIVER's scooter, as ScooterSelection confirmed it: the team rides the
	-- driver's pick, whatever the passenger chose
	local tpl, scooterId = ScooterSelection.TemplateFor(driver)
	local sys = workspace:FindFirstChild("RideSystem")
	local bin = sys and sys:FindFirstChild("Scooters")
	if not tpl then return nil, "no scooter model in ServerStorage.ScooterModels" end
	if not bin then return nil, "Workspace.RideSystem.Scooters missing" end
	if not spawnPart then return nil, "no spawn part" end

	-- Reference the named spawn attachment; never a hard-coded coordinate.
	local a    = spawnPart:FindFirstChild("ScooterSpawn")
	local base = a and a.WorldCFrame or spawnPart.CFrame
	local scooter = buildScooter(tpl, bin, stationId,
		CFrame.new(base.Position + Vector3.new(0, Config.ScooterLift, 0)) * base.Rotation)

	local ride = {
		Scooter = scooter, StationId = stationId,
		Driver = driver, Passenger = passenger,
		CheckpointId = checkpointId,
		Riders = {}, Conns = {},
		Template = tpl,   -- a revive (Relaunch) brings back the same scooter
		Life = 0,         -- goes up with every revive (DeathManager)
	}
	ride.Controller = ScooterController.new(scooter)
	log("controller:", ride.Controller:Describe())

	-- The poof starts round the riders in their booths now and bursts as they are
	-- moved. The same wait lets the assembly settle before the riders are pinned to
	-- it (that needs 0.2 s of it).
	boothPoof(rootPosition(driver), rootPosition(passenger))
	task.wait(TELEPORT_LEAD)
	-- a rider left, reset or died during the lead-in: no ride, and no scooter left behind
	if stillBoarding and not stillBoarding() then
		ride.Controller:Destroy()
		scooter:Destroy()
		return nil, "a rider left before the launch"
	end
	board(ride)
	local missing, missingRole = missingRider(ride)
	if missing then
		for _, h in pairs(ride.Riders) do RiderAttach.Release(h) end
		for _, c in ipairs(ride.Conns) do pcall(function() c:Disconnect() end) end
		ride.Controller:Destroy()
		scooter:Destroy()
		return nil, ("%s (%s) could not be put on the scooter"):format(missing.Name, missingRole)
	end

	RideManager.Rides[scooter] = ride
	if driver    then RideManager.PlayerRide[driver]    = ride end
	if passenger then RideManager.PlayerRide[passenger] = ride end
	ensureStepper()
	funnel("RideStarted", ride)   -- analytics only

	local function push(plr, role)
		if plr and plr.Parent then
			Remotes.StateChanged:FireClient(plr, {
				Phase = "Riding", Role = role,
				StationId = stationId, CheckpointId = checkpointId,
			})
		end
	end
	push(driver, "Driver")
	push(passenger, "Passenger")

	log("ride started at station", stationId, "->", tostring(checkpointId), "on", tostring(scooterId))
	return ride
end

---------------------------------------------------------------- revive
-- A revive (DeathManager): the SAME ride carries on - its run, checkpoints and station stay
-- as they are - on a new scooter, with both riders on it in new characters (they died).
--   1. each rider gets a new character (Main leaves the ride alone meanwhile: Reviving)
--   2. spot() is asked for the chassis CFrame now, the last moment before the scooter
--      appears, so it can look at the spot again
--   3. the old scooter goes and a new one of the same model stands there; the riders are
--      moved to it and, once it has settled, boarded exactly as at the start
-- Errors (and leaves nothing behind) if a rider leaves or the ride ends meanwhile.
local RELAUNCH_SETTLE = 0.3

function RideManager.Relaunch(ride, spot)
	local riders = {}
	for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
		if plr then table.insert(riders, plr) end
	end
	for _, plr in ipairs(riders) do RideManager.Reviving[plr] = true end
	local ok, err = pcall(function()
		-- the dead bodies let go of the old scooter
		for _, h in pairs(ride.Riders) do RiderAttach.Release(h) end
		ride.Riders = {}
		for _, c in ipairs(ride.Conns) do pcall(function() c:Disconnect() end) end
		ride.Conns = {}
		for _, plr in ipairs(riders) do
			if not plr.Parent then error(plr.Name .. " left") end
			plr:LoadCharacter()
			if ride._ended then error("the ride ended") end
		end

		local cf = spot()
		if typeof(cf) ~= "CFrame" then error("no spot to come back at") end
		if ride._ended then error("the ride ended") end

		local sys = workspace:FindFirstChild("RideSystem")
		local bin = sys and sys:FindFirstChild("Scooters")
		local tpl = ride.Template or ScooterSelection.TemplateFor(ride.Driver)
		if not (tpl and bin) then error("no scooter model") end
		local old = ride.Scooter
		if ride.Controller then ride.Controller:Destroy() end
		if old then
			RideManager.Rides[old] = nil
			old:Destroy()
		end
		local scooter = buildScooter(tpl, bin, ride.StationId, cf)
		ride.Scooter = scooter
		ride.Controller = ScooterController.new(scooter)
		ride.BrakeHeld = false
		RideManager.Rides[scooter] = ride
		for _, plr in ipairs(riders) do
			local ch = plr.Character
			if ch then ch:PivotTo(cf + Vector3.new(0, 4, 0)) end
		end
		task.wait(RELAUNCH_SETTLE)
		if ride._ended then error("the ride ended") end
		board(ride)
		local missing, missingRole = missingRider(ride)
		if missing then error(("%s (%s) could not be put back on the scooter"):format(missing.Name, missingRole)) end
		ensureStepper()
	end)
	for _, plr in ipairs(riders) do RideManager.Reviving[plr] = nil end
	if not ok then error(err, 0) end
	relaunched:Fire(ride.Scooter)
	log("ride at station", ride.StationId, "relaunched")
end

function RideManager.IsReviving(player)
	return RideManager.Reviving[player] == true
end

---------------------------------------------------------------- input
-- Server authority, split by role: the DRIVER may only steer, the PASSENGER may
-- only work the motor. Neither can do the other's job, and a player who is not on
-- this ride is ignored entirely.
function RideManager.ApplyInput(player, payload)
	local ride = RideManager.PlayerRide[player]
	-- a ride that went into the water (DeathManager) takes no more input
	if not ride or ride._ended or ride.Down or not ride.Controller then return end
	if typeof(payload) ~= "table" then return end

	-- Each control is applied only when it is sent: one remote carries all of them,
	-- and a message about one (the horn) must never reset another (a missing Steer
	-- would straighten the fork, a missing Throttle would coast).
	if player == ride.Driver then
		if payload.Steer ~= nil then ride.Controller:SetSteer(tonumber(payload.Steer) or 0) end
	elseif player == ride.Passenger then
		if payload.Throttle ~= nil then
			-- the controller sanitises the mode; the hands follow whatever it accepted
			ride.Controller:SetThrottle(payload.Throttle)
			RiderPose.SetAction(ride.Riders.Passenger, ride.Controller.Mode)
		end
		-- the brake held (Space / the Brake pedal): only the screech listens to it
		if payload.Brake ~= nil then ride.BrakeHeld = payload.Brake == true end
	end

	-- the horn: either rider, for their own place on this scooter only, and only
	-- while they are really on it
	if payload.Horn ~= nil then
		local role = (player == ride.Driver and "Driver") or (player == ride.Passenger and "Passenger") or nil
		local held = role and ride.Riders[role]
		setHorn(ride, role, payload.Horn == true and held ~= nil and not held.Released)
	end
end

---------------------------------------------------------------- teardown
-- Back to the lobby spawn, for ONE player, and verified for that player alone.
-- The character has only just been handed back to its own player's machine
-- (RiderAttach.Release) - and a passenger was being simulated by the DRIVER's
-- machine until then - so a machine can still report the old position and undo
-- the move. With real network lag that can arrive well after a second (a player
-- was left in the ocean that way), so:
--   * the move is made by the server AND by the player's own machine
--     (Remotes.ReturnHome), which is what actually simulates the character
--   * it is checked every HOME_CHECK and repeated whenever the character is
--     still (or again) out on the course - more than STRANDED studs from the
--     lobby spawn - until it has stayed in the lobby for HOME_SETTLE. Walking
--     about the lobby never counts as stranded, so the watch can run long
--     enough to catch a late undo without ever pulling back a player who is
--     just walking off.
local STRANDED, HOME_CHECK, HOME_SETTLE, HOME_GIVE_UP = 150, 0.25, 4, 12
local homing = {}   -- [player] = the newest send-home's ticket: a second one takes over the watch

local function sendHome(plr)
	-- a dead rider is not moved: they respawn at the lobby spawn (Main)
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then return end
	local ticket = {}
	homing[plr] = ticket
	local function move()
		StartManager.ReturnToLobby(plr)
		local sp = StartManager.GetLobbySpawn()
		if sp and plr.Parent then
			Remotes.ReturnHome:FireClient(plr, sp.CFrame + Vector3.new(0, 5, 0))
		end
	end
	move()
	task.spawn(function()
		local t0, homeSince, moves = os.clock(), nil, 1
		while plr.Parent and os.clock() - t0 < HOME_GIVE_UP do
			task.wait(HOME_CHECK)
			if homing[plr] ~= ticket then return end         -- a newer send-home watches now
			if RideManager.PlayerRide[plr] then return end   -- already riding again
			local sp   = StartManager.GetLobbySpawn()
			local ch   = plr.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if sp and root then
				if (root.Position - sp.Position).Magnitude > STRANDED then
					homeSince = nil
					moves += 1
					move()
				else
					homeSince = homeSince or os.clock()
					if os.clock() - homeSince >= HOME_SETTLE then
						log(plr.Name, "is back in the lobby (" .. moves .. " move(s))")
						return
					end
				end
			end
		end
		if plr.Parent then print("[Scooter] " .. plr.Name .. " did not settle in the lobby") end
	end)
end
RideManager.SendHome = sendHome   -- also used by DeathManager when a run ends in the water
Players.PlayerRemoving:Connect(function(plr) homing[plr] = nil end)

-- `leaver`: the rider who left the game, when that is why the ride ends. Their
-- partner is sent straight back to the lobby and told why.
function RideManager.End(ride, reason, leaver)
	if not ride or ride._ended then return end
	ride._ended = true
	funnel("RideEnded", ride)   -- analytics only

	for _, c in ipairs(ride.Conns) do pcall(function() c:Disconnect() end) end
	for _, h in pairs(ride.Riders) do RiderAttach.Release(h) end
	if ride.Controller then ride.Controller:Destroy() end

	-- Cleared one at a time on purpose: either role can legitimately be nil (a
	-- player left, or an attach failed), and ipairs over {nil, plr} would stop at
	-- the first nil and silently clean up neither.
	local function clear(plr)
		if not plr then return end
		RideManager.PlayerRide[plr] = nil
		if plr.Parent then
			Remotes.StateChanged:FireClient(plr, {
				Phase = "None",
				Notice = (leaver and plr ~= leaver) and LEFT_NOTICE or nil,
			})
		end
	end
	clear(ride.Driver)
	clear(ride.Passenger)

	RideManager.Rides[ride.Scooter] = nil
	if ride.Scooter then ride.Scooter:Destroy() end

	-- Whoever is still standing goes back to the lobby, whatever ended the ride (their
	-- partner left, a respawn, the anti-cheat): never left on the course where the scooter
	-- was. (DeathManager.Finish sends them too; the newer send-home simply takes over.)
	for _, plr in pairs({ ride.Driver or false, ride.Passenger or false }) do
		if plr and plr ~= leaver and plr.Parent then sendHome(plr) end
	end
	log("ride ended at station", ride.StationId, "(" .. tostring(reason) .. ")")
end

-- `left`: the player has left the game (see End)
function RideManager.EndForPlayer(player, reason, left)
	local ride = RideManager.PlayerRide[player]
	if ride then RideManager.End(ride, reason, left and player or nil) end
end

return RideManager
