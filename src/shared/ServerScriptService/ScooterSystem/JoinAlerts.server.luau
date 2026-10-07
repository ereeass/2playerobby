--=====================================================================
-- JoinAlerts   (server)
--
-- The lobby's JOIN cards (StarterPlayerScripts.JoinAlerts draws them): one card for every
-- player waiting ALONE in a booth, so anyone walking around the lobby can hop in with them.
--
-- Nothing here changes how the booths work. Who is in which booth is TeamManager's; this
-- only LOOKS at it, a few times a second, and publishes the result:
--   ReplicatedStorage.ScooterSystem.WaitingPlayers   one Configuration per waiting player
--       Name = their UserId; attributes UserId, DisplayName, StationId, Role (the FREE
--       role a joiner would get), Since (server time they started waiting alone)
-- Because the list is worked out afresh every scan from the booths' real state, a card is
-- right whatever happened: a partner walking in (card goes), that partner leaving again
-- before START (card comes back), the pick timer sending both home, a launch called off,
-- a death, a respawn, someone leaving the game - every path ends up here the same way.
--
-- A card shows only once a player has been alone SHOW_AFTER seconds (friends walking in
-- together pair up before that, so no card ever flashes for them).
--
--   JoinWaiting (RemoteFunction)  <- a card's JOIN (the waiting player's UserId)
--   -> "ok" | "gone" (taken / no longer waiting) | "cooldown" | "rejoin" | "busy"
-- Every JOIN is checked again here: the joiner must be free in the lobby (no booth, no
-- ride, alive, not seated or on a scooter) and the waiting player still alone. The booth's
-- surroundings are loaded on the joiner's machine first (streaming; usually instant), then -
-- in ONE step, with nothing able to happen in between - everything is checked again, the
-- joiner is put in front of the free booth's glass and goes in through TeamManager.Enter,
-- the very same entry as pressing E there, door walk-in and all. So when two players press
-- JOIN on the same card at once, the first in gets the seat and the other is told it's taken.
-- A teleport poof (Remotes.TeleportFx) marks where they left and where they arrived.
--=====================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Root        = RS:WaitForChild("ScooterSystem")
local Remotes     = Root:WaitForChild("Remotes")
local TeamManager = require(script.Parent:WaitForChild("TeamManager"))
local RideManager = require(script.Parent:WaitForChild("RideManager"))

---------------------------------------------------------------- settings (tune these)
local SHOW_AFTER    = 4      -- seconds alone in a booth before their card shows
local SCAN_EVERY    = 0.25   -- seconds between looks at the booths
local JOIN_COOLDOWN = 3      -- seconds between one player's JOIN presses
local REJOIN_BLOCK  = 30     -- after joining someone, that same player can't be JOINed again for this long
local STREAM_WAIT   = 2      -- at most this long for the booth area to load on the joiner's machine
local FRONT         = 4.8    -- studs out in front of the booth's glass to put the joiner

---------------------------------------------------------------- published list
local list = Root:FindFirstChild("WaitingPlayers")
if not list then
	list = Instance.new("Folder")
	list.Name = "WaitingPlayers"
	list.Parent = Root
end
list:ClearAllChildren()

local joinRemote = Remotes:FindFirstChild("JoinWaiting")
if not joinRemote then
	joinRemote = Instance.new("RemoteFunction")
	joinRemote.Name = "JoinWaiting"
	joinRemote.Parent = Remotes
end

---------------------------------------------------------------- helpers
-- a living character, standing on its own feet (not seated, not on a scooter)
local function freeBody(plr)
	local ch   = plr and plr.Parent and plr.Character
	local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then return nil end
	if hum.Sit or root:FindFirstChild("ScooterRiderWeld") then return nil end
	return ch, hum, root
end

-- the station's one occupant, inside and waiting for a partner, and the free role; else nil
local function loneWaiter(st)
	if st.Phase ~= "Waiting" or next(st.Arriving) ~= nil then return nil end
	local d, p = st.Occupants.Driver, st.Occupants.Passenger
	if (d and p) or not (d or p) then return nil end
	local plr  = d or p
	local free = d and "Passenger" or "Driver"
	local part = st.Parts[free]
	if not (part and part.Parent) then return nil end
	if not plr.Parent then return nil end
	local ch  = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return plr, free, part
end

local function boothOf(part)
	local ref = part:FindFirstChild("CapsuleModel")
	local m = ref and ref.Value
	return (m and m:IsA("Model")) and m or nil
end

-- standing on the ground just in front of the booth's glass, facing in
local function frontSpot(part, hum, root)
	local booth = boothOf(part)
	local pivot = booth and booth.WorldPivot or part.CFrame
	local out   = pivot.LookVector                     -- out through the glass
	local spot  = pivot:PointToWorldSpace(Vector3.new(0, 0, -FRONT))
	local params = RaycastParams.new()
	local skip = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(skip, p.Character) end
	end
	params.FilterDescendantsInstances = skip
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true   -- solid ground only (never a glow column or a trigger)
	local hit = workspace:Raycast(spot + Vector3.new(0, 8, 0), Vector3.new(0, -20, 0), params)
	local groundY = hit and hit.Position.Y or pivot.Position.Y
	local lift = (hum.RigType == Enum.HumanoidRigType.R6) and 3 or (hum.HipHeight + root.Size.Y / 2)
	local pos = Vector3.new(spot.X, groundY + lift + 0.1, spot.Z)
	return CFrame.lookAt(pos, pos - out)
end

-- a move made on the player's own machine too (it simulates the character; a move made
-- only here can be undone by the old position still in flight from there)
local function moveCharacter(plr, ch, cf)
	ch:PivotTo(cf)
	local root = ch:FindFirstChild("HumanoidRootPart")
	if root then root.AssemblyLinearVelocity = Vector3.zero end
	local rh = Remotes:FindFirstChild("ReturnHome")
	if rh and plr.Parent then rh:FireClient(plr, cf) end
end

---------------------------------------------------------------- scan
local alone   = {}   -- [player] = { st, since (server time), at (os.clock) }: waiting alone
local entries = {}   -- [player] = Configuration in the list

local function removeEntry(plr)
	local e = entries[plr]
	if e then
		entries[plr] = nil
		e:Destroy()
	end
end

local function scan()
	local seen = {}
	for _, st in pairs(TeamManager.Stations) do
		local plr, free = loneWaiter(st)
		if plr then
			seen[plr] = true
			local a = alone[plr]
			if not a or a.st ~= st then
				removeEntry(plr)
				a = { st = st, since = workspace:GetServerTimeNow(), at = os.clock() }
				alone[plr] = a
			end
			local e = entries[plr]
			if not e and os.clock() - a.at >= SHOW_AFTER then
				e = Instance.new("Configuration")
				e.Name = tostring(plr.UserId)
				e:SetAttribute("UserId", plr.UserId)
				e:SetAttribute("DisplayName", plr.DisplayName)
				e:SetAttribute("StationId", st.Id)
				e:SetAttribute("Role", free)
				e:SetAttribute("Since", a.since)
				e.Parent = list
				entries[plr] = e
			elseif e and e:GetAttribute("Role") ~= free then
				e:SetAttribute("Role", free)
			end
		end
	end
	for plr in pairs(alone) do
		if not seen[plr] then
			alone[plr] = nil
			removeEntry(plr)
		end
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(scan)
		if not ok then warn("[JoinAlerts] scan failed: " .. tostring(err)) end
		task.wait(SCAN_EVERY)
	end
end)

---------------------------------------------------------------- JOIN
local lastPress  = {}   -- [player] = os.clock() of their last JOIN press
local lastJoined = {}   -- [player] = { userId, at }: whom they last joined through a card

local function busy(plr)
	return TeamManager.PlayerSlot[plr] ~= nil or RideManager.PlayerRide[plr] ~= nil
		or RideManager.IsReviving(plr)
end

local function join(player, userId)
	if typeof(userId) ~= "number" then return "gone" end
	local now = os.clock()
	if now - (lastPress[player] or 0) < JOIN_COOLDOWN then return "cooldown" end

	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player or not entries[target] then return "gone" end
	local recent = lastJoined[player]
	if recent and recent.userId == userId and now - recent.at < REJOIN_BLOCK then return "rejoin" end
	if busy(player) or not freeBody(player) then return "busy" end
	local a = alone[target]
	local st = a and a.st
	if not st then return "gone" end
	local w, _, part = loneWaiter(st)
	if w ~= target then return "gone" end
	lastPress[player] = now   -- a real try: the cooldown starts
	local pressedWith = player.Character

	-- the booth's surroundings on the joiner's machine first (usually loaded already)
	pcall(player.RequestStreamAroundAsync, player, part.Position, STREAM_WAIT)

	-- From here on nothing yields: the checks, the move and the entry happen in one step, so
	-- nothing can change in between. Two JOINs on one card: the first in gets the seat.
	if not (player.Parent and target.Parent) then return "gone" end
	if busy(player) then return "busy" end
	local ch, hum, root = freeBody(player)
	if not ch or ch ~= pressedWith then return "busy" end   -- died / respawned meanwhile: that press is void
	local w2, _, part2 = loneWaiter(st)
	if w2 ~= target or part2 ~= part then return "gone" end

	local from = root.Position
	local cf = frontSpot(part, hum, root)
	moveCharacter(player, ch, cf)
	TeamManager.Enter(player, part)
	local slot = TeamManager.PlayerSlot[player]
	if not (slot and slot.station == st) then return "gone" end

	removeEntry(target)   -- off every screen at once (the next scan would do it anyway)
	lastJoined[player] = { userId = userId, at = os.clock() }
	pcall(function() Remotes.TeleportFx:FireAllClients({ from, cf.Position }, 0.1) end)
	return "ok"
end

joinRemote.OnServerInvoke = function(player, userId)
	local ok, result = pcall(join, player, userId)
	if not ok then
		warn("[JoinAlerts] " .. tostring(result))
		return "gone"
	end
	return result
end

Players.PlayerRemoving:Connect(function(plr)
	alone[plr] = nil
	removeEntry(plr)
	lastPress[plr] = nil
	lastJoined[plr] = nil
end)
