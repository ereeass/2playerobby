--=====================================================================
-- AntiCheat   (ScooterSystem, server)
--
-- The owners' rule: a legit player must NEVER be punished because a check is unsure.
-- So this protects other players first and punishes almost never.
--
-- Rewards, purchases, spins, daily claims, skips, revives and ownership are decided only
-- on the server by their own modules; checkpoints and the finish are read from positions
-- on the server (CheckpointProgress, RunTimer). What a client can still do is move the
-- scooter it simulates (the driver owns its physics), so rides are watched, 4x a second,
-- only while rides exist.
--
--   PROTECT (never a punishment)  a scooter spinning wildly (> SPIN_LIMIT), moving far
--       faster than a ride can (> GHOST_SPEED sideways) or jumping a teleport's distance
--       is made a "ghost" for GHOST_TIME seconds: it passes through OTHER players'
--       scooters (it still drives on everything else exactly as before), so it can't
--       fling anyone. The player keeps riding; the run stays valid; nothing is shown.
--       A legit scooter thrown by a physics glitch just gets the same harmless ghosting.
--   ACT (only evidence with no legit explanation) - the run is invalidated and the ride
--       ended (both riders back to the lobby, with a notice). Never a kick or a ban.
--       TELEPORTS   TP_REPEAT separate teleport-sized jumps (> TP_MIN studs sideways, far
--                   beyond any lag burst) within TP_WINDOW seconds, with no server move
--                   involved. A physics glitch can throw a scooter once; not over and over.
--       FLYING      FLY_TIME seconds with no ground under it, not falling, AND travelling
--                   FLY_TRAVEL studs sideways meanwhile (a stuck or landed scooter never does).
--   Never judged at all: whenever the SERVER owns or moves the scooter (every obstacle
--   throw, skip, troll effect, revive, spawn and portal) and GRACE seconds after; a ride
--   that is down; a position that hasn't changed (lag) - moves are measured over the whole
--   time since the last one, so a lag spike's catch-up can't look like a teleport.
-- Speed on its own is only noted (RunTimer logs it), never punished.
-- Also: walking characters don't collide with each other (they already never touch
-- scooters or riders), so nobody can be flung on foot.
--=====================================================================

local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local RS             = game:GetService("ReplicatedStorage")

local Remotes     = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local RideManager = require(script.Parent:WaitForChild("RideManager"))
local RunTimer    = require(script.Parent:WaitForChild("RunTimer"))
local Webhook     = require(script.Parent:WaitForChild("AntiCheatWebhook"))   -- the team's Discord

-- REPORT-ONLY (the owners' trial): the two ride-ending rules only report to Discord. Flip to
-- false once the reports show they only ever catch real cheaters. Fling protection (ghosting)
-- and the leaderboard's route check (RunTimer) work either way.
local REPORT_ONLY = true

local EVERY       = 0.25   -- seconds between checks
local GRACE       = 2.5    -- seconds after the server held or moved the scooter
local GHOST_SPEED = 60     -- studs/s sideways (top speed ~21)
local SPIN_LIMIT  = 45     -- rad/s
local GHOST_TIME  = 5      -- seconds a ghost lasts after the last sign
local TP_MIN, TP_SPEED, TP_SLACK = 100, 60, 40   -- a teleport-sized jump
local TP_REPEAT, TP_WINDOW = 3, 30
local TP_SPAN = 1        -- seconds a jump is looked for over (a teleport can reach the server in pieces)
local FLY_TIME, FLY_DROP, FLY_RAY, FLY_TRAVEL = 6, 20, 14, 200

local BODY, GHOST = "ScooterBody", "ScooterGhost"
local NOTICE = "Unusual movement was detected, so this ride was ended. You're back in the lobby."

local AntiCheat = {}
local watch = {}   -- [ride] = state

-- nobody flings anyone on foot
pcall(function() PhysicsService:CollisionGroupSetCollidable("Characters", "Characters", false) end)

-- a ghost scooter: exactly like ScooterBody, except it passes through other scooters
local ghostReady = pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered(GHOST) then PhysicsService:RegisterCollisionGroup(GHOST) end
	for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if g.name ~= GHOST then
			PhysicsService:CollisionGroupSetCollidable(GHOST, g.name, PhysicsService:CollisionGroupsAreCollidable(BODY, g.name))
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GHOST, BODY, false)
	PhysicsService:CollisionGroupSetCollidable(GHOST, GHOST, PhysicsService:CollisionGroupsAreCollidable(BODY, BODY))
end)

local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
ray.IgnoreWater = false

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- who simulates this part (nil = the server). Roblox throws on an anchored part, or one welded
-- to an anchored part (a scooter held for a countdown, revive, cinematic...): the server's.
local function ownerOf(part)
	local ok, owner = pcall(part.GetNetworkOwner, part)
	return ok and owner or nil
end

local function setGhost(ride, st, on)
	if not ghostReady or st.ghost == on then return end
	st.ghost = on
	if on then
		st.ghostParts = {}
		for _, p in ipairs(ride.Scooter:GetDescendants()) do
			if p:IsA("BasePart") and p.CollisionGroup == BODY then
				p.CollisionGroup = GHOST
				table.insert(st.ghostParts, p)
			end
		end
	else
		for _, p in ipairs(st.ghostParts or {}) do
			if p.Parent and p.CollisionGroup == GHOST then p.CollisionGroup = BODY end
		end
		st.ghostParts = nil
	end
end

-- who to report: whoever simulates the scooter (the driver's machine), and their partner
local function report(ride, what, detail, certainty, action)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	local owner = (chassis and ownerOf(chassis)) or ride.Driver
	if not owner then return end
	local partner = (owner == ride.Driver) and ride.Passenger or ride.Driver
	pcall(Webhook.Report, owner, {
		What = what, Detail = detail, Certainty = certainty, Action = action,
		Partner = partner and partner ~= owner and ("%s (@%s) - UserId %d"):format(partner.DisplayName, partner.Name, partner.UserId) or nil,
	})
end

local function protect(ride, st, now, why, what, certainty)
	st.ghostUntil = now + GHOST_TIME
	if not st.ghost then
		setGhost(ride, st, true)
		print(("[AntiCheat] %s: %s - passes through other scooters for a moment (no action)"):format(ride.Scooter.Name, why))
		report(ride, what, why, certainty, "None - it passed through other scooters for 5s (nothing else)")
	end
end

local function act(ride, st, why)
	if st.done then return end
	if REPORT_ONLY then
		report(ride, st.what or "Violation", why, st.certainty or 90,
			"None - REPORT-ONLY mode (would have ended the ride and invalidated the run)")
		print(("[AntiCheat] %s: %s - report-only mode, no action"):format(ride.Scooter.Name, why))
		st.tps, st.airSince = {}, nil   -- counted afresh (the report itself has a cooldown)
		return
	end
	st.done = true
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	local owner = chassis and ownerOf(chassis)
	warn(("[AntiCheat] %s (driver %s, owner %s): %s - run invalidated, ride ended"):format(
		ride.Scooter and ride.Scooter.Name or "?", ride.Driver and ride.Driver.Name or "-",
		owner and owner.Name or "server", why))
	report(ride, st.what or "Violation", why, st.certainty or 90, "Ride ended (both back to the lobby), run invalidated")
	pcall(RunTimer.Invalidate, ride, "anti-cheat: " .. why)
	for _, plr in ipairs({ ride.Driver, ride.Passenger }) do
		if plr and plr.Parent then pcall(function() Remotes.Notice:FireClient(plr, NOTICE) end) end
	end
	pcall(RideManager.End, ride, "anti-cheat")
end

local function stateFor(ride, chassis, now)
	local st = watch[ride]
	if st and st.chassis ~= chassis then
		if st.conn then st.conn:Disconnect() end
		st = nil   -- a revive put it on a new scooter
	end
	if not st then
		st = { chassis = chassis, graceUntil = now + GRACE, tps = {} }
		-- a move made by a server script is never judged (a client's own move doesn't fire this)
		st.conn = chassis:GetPropertyChangedSignal("CFrame"):Connect(function()
			st.graceUntil = os.clock() + GRACE
			st.pos, st.airSince = nil, nil
		end)
		watch[ride] = st
	end
	return st
end

local function check(ride, st, chassis, now)
	if st.ghost and now > (st.ghostUntil or 0) then setGhost(ride, st, false) end
	if ownerOf(chassis) == nil then st.graceUntil = now + GRACE end
	local pos = chassis.Position
	if now < st.graceUntil or not st.pos then
		st.pos, st.t, st.airSince, st.hist = pos, now, nil, { { pos, now } }
		return
	end

	-- a wild spin: protect the others
	local spin = chassis.AssemblyAngularVelocity.Magnitude
	if spin > SPIN_LIMIT then protect(ride, st, now, ("spinning at %d rad/s"):format(spin), "Wild spinning (possible fling)", 35) end

	if pos ~= st.pos then
		local dt = math.max(now - st.t, 1 / 60)
		local d = flat(pos - st.pos).Magnitude
		st.pos, st.t = pos, now
		-- the last TP_SPAN seconds of positions, plus one older as the far end (a lag spike's
		-- catch-up is measured over the whole freeze, so it never looks like a jump)
		local h = st.hist
		table.insert(h, { pos, now })
		while #h > 2 and now - h[2][2] >= TP_SPAN do table.remove(h, 1) end
		local far = h[1]
		local span = math.max(now - far[2], 1 / 60)
		local jump = flat(pos - far[1]).Magnitude
		if jump > TP_MIN and jump > TP_SPEED * span + TP_SLACK then
			st.hist = { { pos, now } }   -- counted once
			protect(ride, st, now, ("jumped %d studs in %.2fs"):format(jump, span), "Teleport-sized jump", 60)
			for i = #st.tps, 1, -1 do if now - st.tps[i] > TP_WINDOW then table.remove(st.tps, i) end end
			table.insert(st.tps, now)
			if #st.tps >= TP_REPEAT then
				st.what, st.certainty = "Repeated teleporting", 97
				return act(ride, st, ("teleported %d times in %ds"):format(#st.tps, TP_WINDOW))
			end
		elseif d / dt > GHOST_SPEED then
			protect(ride, st, now, ("moving %d studs/s (top speed ~21)"):format(d / dt), "Impossible speed",
				math.clamp(40 + (d / dt - GHOST_SPEED) / 5, 40, 80))
		end
	end

	-- flying: long in the air, not falling, and travelling
	ray.FilterDescendantsInstances = { ride.Scooter, ride.Driver and ride.Driver.Character, ride.Passenger and ride.Passenger.Character }
	if workspace:Raycast(pos, Vector3.new(0, -FLY_RAY, 0), ray) then
		st.airSince = nil
	elseif not st.airSince then
		st.airSince, st.airPos = now, pos
	elseif now - st.airSince >= FLY_TIME and st.airPos.Y - pos.Y < FLY_DROP
		and flat(pos - st.airPos).Magnitude >= FLY_TRAVEL then
		st.what, st.certainty = "Flying", 95
		return act(ride, st, ("flying %d studs in %.1fs without falling"):format(flat(pos - st.airPos).Magnitude, now - st.airSince))
	end
end

-- fling protection runs EVERY frame (cheap: two numbers per ride): the moment a scooter the
-- driver's machine controls is going wild, it can't touch anyone else's scooter
local function flingGuard(now)
	for ride, st in pairs(watch) do
		local chassis = st.chassis
		if not st.done and chassis.Parent and not ride._ended and not ride.Down and now >= st.graceUntil
			and ownerOf(chassis) ~= nil then
			local v = chassis.AssemblyLinearVelocity
			local fast = Vector3.new(v.X, 0, v.Z).Magnitude
			local spin = chassis.AssemblyAngularVelocity.Magnitude
			if fast > GHOST_SPEED then
				protect(ride, st, now, ("moving %d studs/s (top speed ~21)"):format(fast), "Impossible speed",
					math.clamp(40 + (fast - GHOST_SPEED) / 5, 40, 80))
			elseif spin > SPIN_LIMIT then
				protect(ride, st, now, ("spinning at %d rad/s"):format(spin), "Wild spinning (possible fling)", 35)
			end
		end
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	local okG, errG = pcall(flingGuard, os.clock())
	if not okG then warn("[AntiCheat] " .. tostring(errG)) end
	acc += dt
	if acc < EVERY then return end
	acc = 0
	local now = os.clock()
	for ride, st in pairs(watch) do
		if ride._ended or RideManager.Rides[ride.Scooter] ~= ride then
			if st.conn then st.conn:Disconnect() end
			watch[ride] = nil
		end
	end
	for _, ride in pairs(RideManager.Rides) do
		local chassis = ride.Scooter and ride.Scooter.PrimaryPart
		if chassis and not ride._ended and not ride.Down then
			local st = stateFor(ride, chassis, now)
			if not st.done then
				local ok, err = pcall(check, ride, st, chassis, now)
				if not ok then warn("[AntiCheat] " .. tostring(err)) end
			end
		elseif watch[ride] then
			watch[ride].graceUntil, watch[ride].pos = now + GRACE, nil   -- down: the next life starts afresh
		end
	end
end)

RideManager.Relaunched:Connect(function(scooter)
	local ride = RideManager.Rides[scooter]
	local st = ride and watch[ride]
	if st then st.graceUntil, st.pos, st.tps = os.clock() + GRACE, nil, {} end
end)

return AntiCheat
