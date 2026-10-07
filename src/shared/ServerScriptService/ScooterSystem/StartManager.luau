-- Resolves where a team starts, and moves characters to and from the lobby.
-- Stateless apart from a cached lobby spawn: it only reads Workspace, so
-- TeamManager drives it.
--
-- Spawning the vehicle itself belongs to RideManager, not here.

local RS = game:GetService("ReplicatedStorage")

local Shared      = RS:WaitForChild("ScooterSystem"):WaitForChild("Shared")
local Config      = require(Shared:WaitForChild("Config"))
local Checkpoints = require(Shared:WaitForChild("Checkpoints"))

local StartManager = {}
local cachedSpawn = nil

local function startLocations()
	local sys = workspace:FindFirstChild("RideSystem")
	return sys and sys:FindFirstChild("StartLocations") or nil
end

-- A start part by name: under StartLocations first, else anywhere in Workspace.
-- A checkpoint's parking lot carries its own bay markers (Checkpoint 1 Parking
-- Lot > Bays > BayN > Checkpoint1_BayN), so moving or turning the lot moves where,
-- and which way, its rides start.
local function findStart(name)
	local locs = startLocations()
	local p = (locs and locs:FindFirstChild(name, true)) or workspace:FindFirstChild(name, true)
	return (p and p:IsA("BasePart")) and p or nil
end

-- A scooter still standing in a bay (a team that has not driven off yet) keeps
-- the next team out of it.
local BAY_CLEAR = 4   -- studs from the bay's spawn point
local function bayTaken(bay)
	local sys = workspace:FindFirstChild("RideSystem")
	local bin = sys and sys:FindFirstChild("Scooters")
	local spot = bay:FindFirstChild("ScooterSpawn")
	spot = spot and spot.WorldPosition or bay.Position
	for _, s in ipairs(bin and bin:GetChildren() or {}) do
		local p = s:IsA("Model") and s.PrimaryPart
		if p and ((p.Position - spot) * Vector3.new(1, 0, 1)).Magnitude < BAY_CLEAR then return true end
	end
	return false
end

-- A checkpoint with parking bays (BayPrefix, e.g. "Checkpoint1_Bay") gives every
-- booth station its own: <BayPrefix><station id>. If that one is still taken,
-- the nearest free bay of the same checkpoint; if all are, its own anyway.
local MAX_BAYS = 12
local function resolveBay(prefix, stationId)
	local own = findStart(prefix .. tostring(stationId))
	if own and not bayTaken(own) then return own end
	local best, bestD
	for i = 1, MAX_BAYS do
		local b = findStart(prefix .. i)
		if b and b ~= own and not bayTaken(b) then
			local d = own and (b.Position - own.Position).Magnitude or 0
			if not bestD or d < bestD then best, bestD = b, d end
		end
	end
	return best or own
end

-- Always resolves to a NAMED part (see findStart). Nothing here invents a coordinate.
function StartManager.ResolveSpawnPart(checkpointId, stationId)
	local cp = Checkpoints.GetById(checkpointId)
	if cp and cp.BayPrefix and stationId ~= nil then
		local bay = resolveBay(cp.BayPrefix, stationId)
		if bay then return bay end
	end
	if cp and cp.SpawnPartName then
		local p = findStart(cp.SpawnPartName)
		if p then return p end
	end
	return findStart(Config.FallbackStartPlate)
end

function StartManager.PlaceCharacter(player, cf)
	local ch = player and player.Character
	if not ch or not ch.PrimaryPart then return false end
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = false end          -- never leave a character anchored
	ch:PivotTo(cf)
	if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
	-- The player's own machine simulates its character, so it makes the move too: a move made
	-- only here can be undone by the old position still in flight from there - leaving them
	-- standing in a closed booth they are no longer in (as RideManager.SendHome does)
	local remotes = RS.ScooterSystem:FindFirstChild("Remotes")
	local returnHome = remotes and remotes:FindFirstChild("ReturnHome")
	if returnHome and player.Parent then returnHome:FireClient(player, cf) end
	return true
end

function StartManager.ReleaseCharacter(player)
	local ch = player and player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = false end
end

-- cached; re-resolved only if the cached one is destroyed or disabled
function StartManager.GetLobbySpawn()
	if cachedSpawn and cachedSpawn.Parent and cachedSpawn.Enabled then return cachedSpawn end
	cachedSpawn = nil
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Enabled then cachedSpawn = d; break end
	end
	return cachedSpawn
end

function StartManager.ReturnToLobby(player)
	StartManager.ReleaseCharacter(player)
	local sp = StartManager.GetLobbySpawn()
	if sp then
		StartManager.PlaceCharacter(player, sp.CFrame + Vector3.new(0, 5, 0))
	end
end

return StartManager
