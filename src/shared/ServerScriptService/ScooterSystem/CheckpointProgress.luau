--=====================================================================
-- CheckpointProgress   (server)
--
-- Each player's checkpoint progress, kept for good, and what a pair may start from.
--
--   Saved     the HIGHEST checkpoint (its Order in Shared.Checkpoints) the player has
--             reached, as CheckpointProgress in their save, through SettingsServer's
--             PlayerData bindables (server only: no client can write it). Everything up to
--             it is theirs; everyone has checkpoint 1. SettingsServer keeps the higher of
--             the stored and the written value for this key, so a failed load, a stale
--             write or a crash can never lower it. A new unlock is written at once.
--   A pair    may start from a released checkpoint up to the LOWER of their two progresses
--             (Checkpoints.DuoLimit); TeamManager builds the booth menu and checks the
--             pick with MenuFor / CanStart. Nothing belongs to a partner: each player keeps
--             their own progress whoever they ride with.
--   Reaching  a checkpoint means driving onto its LOT - the Model with a CheckpointId
--             attribute (Checkpoint 2 Beach Lot, ...), anywhere on its Ground, from any
--             side - or through its arrival part (a part with a CheckpointId attribute,
--             e.g. Checkpoint5_Arrival). It counts only when BOTH riders of one scooter get
--             there on the same ride - both still aboard and alive, within PAIR_WINDOW of each
--             other (they needn't touch it on the same frame). Rides count checkpoint by
--             checkpoint: from where the ride started only the NEXT checkpoint can be
--             reached, so none is skipped, and one already reached on this ride does
--             nothing. Reaching it gives it to each rider who didn't have it yet; only
--             they get the popup (Remotes.CheckpointUnlocked ->
--             StarterPlayerScripts.CheckpointUnlockPopup). Touching one you already own
--             never does.
--   Dying, resetting, leaving or swapping partners never takes anything away.
--
-- Also answers ScooterSelection.Progress.HasCheckpoint (scooters unlocked by a checkpoint).
--=====================================================================

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local RS                  = game:GetService("ReplicatedStorage")

local Root        = RS:WaitForChild("ScooterSystem")
local Remotes     = Root:WaitForChild("Remotes")
local Shared      = Root:WaitForChild("Shared")
local Config      = require(Shared:WaitForChild("Config"))
local Checkpoints = require(Shared:WaitForChild("Checkpoints"))

local RideManager      = require(script.Parent:WaitForChild("RideManager"))
local ScooterSelection = require(script.Parent:WaitForChild("ScooterSelection"))

-- this world's own save (WorldConfig.CheckpointSaveKey): World 2 never unlocks from World 1
local KEY         = require(RS:WaitForChild("WorldConfig")).CheckpointSaveKey or "CheckpointProgress"
local PAIR_WINDOW = 4      -- seconds allowed between the two riders passing the same arrival
local MIN_DEPTH   = 8      -- arrival parts are thin; checked at least this deep so a fast scooter can't skip one

local Progress = {}
local changed = Instance.new("BindableEvent")
Progress.Changed = changed.Event   -- (player): their progress loaded, or went up
local reachedEvent = Instance.new("BindableEvent")
-- (scooter, order): that ride's riders reached checkpoint `order` together (RunTimer's splits).
-- The scooter model, not the ride table: a BindableEvent hands its listeners a COPY of any table
-- (so a ride table would never match RunTimer's own), while an Instance arrives as itself.
Progress.Reached = reachedEvent.Event

-- Studio tests only: while true nothing is written to anyone's save
Progress.TestMode = false

local sessions = {}   -- [player] = { highest = order, loaded = bool }
Progress._sessions = sessions

local function log(...) if Config.DebugLogging then print("[Checkpoints]", ...) end end

--------------------------------------------------------------------- player data
local dataApi
local function data()
	if dataApi and dataApi.Parent then return dataApi end
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 10)
	return dataApi
end

local function load(player)
	local s = { highest = 1, loaded = false }
	sessions[player] = s
	local api = data()
	local value, state = nil, "failed"
	if api then value, state = api.Get:Invoke(player, KEY) end
	if sessions[player] ~= s then return end            -- left while loading
	local n = tonumber(value)
	if n and n == n then
		-- an unlock made while this was loading is kept too
		s.highest = math.max(s.highest, math.clamp(math.floor(n), 1, Checkpoints.MaxOrder()))
	end
	s.loaded = true
	log(player.Name, "has checkpoints up to", s.highest, "(save: " .. tostring(state) .. ")")
	changed:Fire(player)
end

local function save(player, order)
	if Progress.TestMode then return end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local api = data()
	if not api then return end
	task.spawn(function()
		-- written straight away; if that fails it stays queued and SettingsServer retries it
		-- (and writes it when they leave, or the server shuts down)
		if not api.SaveNow:Invoke(player, KEY, order) then
			warn("[Checkpoints] couldn't save " .. player.Name .. "'s checkpoint " .. order .. " yet; retrying")
		end
	end)
end

--------------------------------------------------------------------- queries
-- (highest checkpoint Order, whether their save has loaded)
function Progress.Get(player)
	local s = player and sessions[player]
	return s and s.highest or 1, s ~= nil and s.loaded
end

-- the highest checkpoint this pair may start from (either may be nil: just the other's)
function Progress.LimitFor(a, b)
	return Checkpoints.DuoLimit(a and (Progress.Get(a)) or nil, b and (Progress.Get(b)) or nil)
end

function Progress.MenuFor(a, b)
	return Checkpoints.MenuFor(Progress.LimitFor(a, b))
end

function Progress.CanStart(a, b, id)
	return Checkpoints.IsAccessible(id, Progress.LimitFor(a, b))
end

-- Gives `order` to the player if it's the next one they haven't got. True only when it was
-- new for them (the popup goes with that, and nothing else).
function Progress.Award(player, order)
	local s = sessions[player]
	if not s or type(order) ~= "number" then return false end
	if order <= s.highest then return false end            -- theirs already
	if order > s.highest + 1 then return false end         -- never skip one
	s.highest = order
	save(player, order)
	changed:Fire(player)
	return true
end

ScooterSelection.Progress.HasCheckpoint = function(player, checkpoint)
	local order = type(checkpoint) == "number" and checkpoint or Checkpoints.OrderOf(checkpoint)
	return order ~= nil and (Progress.Get(player)) >= order
end

--------------------------------------------------------------------- reaching checkpoints
local arrivals = {}   -- [arrival part] = checkpoint Order

local function track(p)
	if not p:IsA("BasePart") then return end
	local order = Checkpoints.OrderOf(p:GetAttribute("CheckpointId"))
	if order then arrivals[p] = order end
end
for _, d in ipairs(workspace:GetDescendants()) do track(d) end
workspace.DescendantAdded:Connect(track)
workspace.DescendantRemoving:Connect(function(d) arrivals[d] = nil end)

-- Each checkpoint's lot: the floor plan of its Ground (the deck's own orientation, so a
-- turned lot works), from just under the deck to well above it. Riders anywhere on it have
-- reached that checkpoint, whichever way the road comes in.
local LOT_ABOVE, LOT_BELOW = 16, 3
local lots = {}   -- [lot model] = { order, frame, min, max }

local function measureLot(lot)
	local order = Checkpoints.OrderOf(lot:GetAttribute("CheckpointId"))
	if not order then return end
	local ground = lot:FindFirstChild("Ground") or lot
	local parts, deck = {}, nil
	for _, p in ipairs(ground:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			if not deck or p.Size.X * p.Size.Z > deck.Size.X * deck.Size.Z then deck = p end
		end
	end
	if not deck then return end
	local look = deck.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	local frame = CFrame.lookAt(deck.Position, deck.Position + look.Unit)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in ipairs(parts) do
		local h = p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
			local c = frame:PointToObjectSpace((p.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position)
			lo, hi = lo:Min(c), hi:Max(c)
		end end end
	end
	lots[lot] = { order = order, frame = frame, min = lo - Vector3.new(0, LOT_BELOW, 0), max = hi + Vector3.new(0, LOT_ABOVE, 0) }
end

local function onLot(z, pos)
	local p = z.frame:PointToObjectSpace(pos)
	return p.X >= z.min.X and p.X <= z.max.X and p.Y >= z.min.Y and p.Y <= z.max.Y and p.Z >= z.min.Z and p.Z <= z.max.Z
end

for _, c in ipairs(workspace:GetChildren()) do
	if c:IsA("Model") and c:GetAttribute("CheckpointId") then measureLot(c) end
end
workspace.ChildAdded:Connect(function(c)
	if c:IsA("Model") and c:GetAttribute("CheckpointId") then task.defer(measureLot, c) end
end)
workspace.ChildRemoved:Connect(function(c) lots[c] = nil end)
do
	local names = {}
	for lot, z in pairs(lots) do table.insert(names, z.order .. "=" .. lot.Name) end
	table.sort(names)
	log("checkpoint lots:", table.concat(names, ", "))
end

local function inside(part, pos)
	local p, s = part.CFrame:PointToObjectSpace(pos), part.Size
	return math.abs(p.X) * 2 <= math.max(s.X, MIN_DEPTH)
		and math.abs(p.Y) * 2 <= math.max(s.Y, MIN_DEPTH)
		and math.abs(p.Z) * 2 <= math.max(s.Z, MIN_DEPTH)
end

-- a rider still on this scooter, in the game and alive
local function aboard(ride, role)
	local h = ride.Riders and ride.Riders[role]
	local plr = h and h.Player
	if not h or h.Released or not plr or not plr.Parent then return nil end
	if h.Humanoid and h.Humanoid.Health <= 0 then return nil end
	return h
end

-- per ride: the last checkpoint it has reached, and when each rider passed the next one
local rides = setmetatable({}, { __mode = "k" })
-- both riders hear which checkpoint's area they're in (StarterPlayerScripts.AreaMusic plays its music)
local function tellArea(ride, order)
	for _, plr in ipairs({ ride.Driver, ride.Passenger }) do
		if typeof(plr) == "Instance" and plr.Parent == Players then Remotes.AreaChanged:FireClient(plr, order) end
	end
end

local function stateOf(ride)
	local st = rides[ride]
	if not st then
		st = { reached = Checkpoints.OrderOf(ride.CheckpointId) or 1, seen = {} }
		rides[ride] = st
		tellArea(ride, st.reached)     -- where this ride started
	end
	return st
end

-- The last checkpoint (Order) this ride has reached - where it started, until it reaches the
-- next one - or nil before the ride is being followed. Read only (CourseProgress: the bar).
function Progress.RideReached(ride)
	local st = ride and rides[ride]
	return st and st.reached or nil
end

local function reach(st, order, players, ride)
	st.reached = order
	if ride and ride.Scooter then reachedEvent:Fire(ride.Scooter, order) end
	if ride then tellArea(ride, order) end
	st.seen = {}
	local cp = Checkpoints.ByOrder(order)
	log(players[1].Name, "and", players[2].Name, "reached", cp and cp.DisplayName or order)
	for _, plr in ipairs(players) do
		if Progress.Award(plr, order) and cp and typeof(plr) == "Instance" and plr.Parent == Players then
			Remotes.CheckpointUnlocked:FireClient(plr, {
				Id = cp.Id, Name = cp.DisplayName, Order = cp.Order, Biome = cp.Biome, Color = Checkpoints.ColorOf(cp),
			})
		end
	end
end

RunService.Heartbeat:Connect(function()
	if next(arrivals) == nil and next(lots) == nil then return end
	local now = os.clock()
	for _, ride in pairs(RideManager.Rides) do
		if not ride._ended and not ride.Down then
			local d, p = aboard(ride, "Driver"), aboard(ride, "Passenger")
			if d and p then
				local st = stateOf(ride)
				local want = st.reached + 1
				for _, h in ipairs({ d, p }) do
					local root = h.Root
					if root and root.Parent then
						local pos, there = root.Position, false
						for lot, z in pairs(lots) do
							if z.order == want and lot.Parent and onLot(z, pos) then there = true break end
						end
						if not there then
							for part, order in pairs(arrivals) do
								if order == want and part.Parent and inside(part, pos) then there = true break end
							end
						end
						if there then st.seen[h.Player] = now end
					end
				end
				local td, tp = st.seen[d.Player], st.seen[p.Player]
				if td and tp and math.abs(td - tp) <= PAIR_WINDOW then
					reach(st, want, { d.Player, p.Player }, ride)
				end
			end
		end
	end
end)

--------------------------------------------------------------------- players
Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
-- their progress is already saved (each unlock is written when it happens, and
-- SettingsServer writes anything still pending as they leave)
Players.PlayerRemoving:Connect(function(player) sessions[player] = nil end)

return Progress
