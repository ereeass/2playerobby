-- WorldUnlock   (server)
--
-- Remembers, for good, which players have beaten THIS world (driven their scooter over the
-- finish line). Saved as <WorldConfig.FinishUnlocks> = true (World 1: "BeatWorld1") in the
-- player's save (SettingsServer's PlayerData, server only, so no client can set it) and
-- mirrored on the Player as that attribute so portals and clients can read it.
-- Also loads (read only) every unlock this world's portals ask for (each WorldPortal's
-- RequiresUnlock), so a portal to a world you've unlocked elsewhere opens here too.
--
-- A finish is ANY ride's chassis crossing a gate tagged "FinishLine" from its back to its
-- front (the same rule RunTimer uses), so rides that continued from a saved checkpoint
-- count too - RunTimer only times rides that start at Checkpoint 1. RunTimer.RunCompleted
-- is also listened to, as a backup.
--
-- Other server scripts: WorldUnlock.Unlocked (BindableEvent, fired with the player)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SSS               = game:GetService("ServerScriptService")

local ScooterSystem = SSS:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))

-- Analytics only (ScooterSystem.Funnels): funnel(...) reports what already happened, in its
-- own protected thread, so it can never change or hold up anything here.
local function funnel(name, ...)
	local args = table.pack(...)
	task.spawn(function()
		local ok, F = pcall(require, ScooterSystem:FindFirstChild("Funnels"))
		if ok and type(F) == "table" and type(F[name]) == "function" then
			pcall(F[name], table.unpack(args, 1, args.n))
		end
	end)
end

local World      = require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig"))
local KEY        = World.FinishUnlocks or "BeatWorld1"
local FINISH_TAG = "FinishLine"
local PORTAL_TAG = "WorldPortal"
local MAX_STEP   = 80   -- studs: a longer jump in one update (a revive, a teleport) never counts as crossing

local unlockedEvent = Instance.new("BindableEvent")
unlockedEvent.Name = "Unlocked"
unlockedEvent.Parent = script

local dataApi
do
	local settings = SSS:WaitForChild("SettingsServer", 30)
	dataApi = settings and settings:WaitForChild("PlayerData", 30)
	if not dataApi then warn("[WorldUnlock] PlayerData not found; unlocks last for this session only") end
end

local function unlock(plr)
	if typeof(plr) ~= "Instance" or plr.Parent ~= Players then return end
	if plr:GetAttribute(KEY) == true then return end
	plr:SetAttribute(KEY, true)
	unlockedEvent:Fire(plr)
	if dataApi then
		task.spawn(function()
			local ok, saved = pcall(function() return dataApi.SaveNow:Invoke(plr, KEY, true) end)
			if not (ok and saved) then
				-- SaveNow keeps it queued on failure; Set makes sure it is written on leaving
				pcall(function() dataApi.Set:Invoke(plr, KEY, true) end)
			end
		end)
	end
end

---------------------------------------------------------------- loading
-- this world's own unlock, plus every unlock a portal here needs
local function keysToLoad()
	local keys = { [KEY] = true }
	for _, portal in ipairs(CollectionService:GetTagged(PORTAL_TAG)) do
		local need = portal:GetAttribute("RequiresUnlock")
		if type(need) == "string" and need ~= "" then keys[need] = true end
	end
	return keys
end

local function onPlayer(plr)
	if not dataApi then return end
	for key in pairs(keysToLoad()) do
		local ok, value = pcall(function() return dataApi.Get:Invoke(plr, key) end)
		if ok and value == true and plr.Parent == Players then plr:SetAttribute(key, true) end
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, plr) end

---------------------------------------------------------------- finishing
local function crossed(gate, a, b)
	local cf, size = gate.CFrame, gate.Size
	local pa, pb = cf:PointToObjectSpace(a), cf:PointToObjectSpace(b)
	if pa.Z > 0 and pb.Z <= 0 then   -- +Z is a gate's back: the side riders come from
		local at = pa:Lerp(pb, pa.Z / (pa.Z - pb.Z))
		return math.abs(at.X) <= size.X / 2 and math.abs(at.Y) <= size.Y / 2
	end
	return false
end

local lastPos = {}   -- [ride] = chassis position last frame

RunService.Heartbeat:Connect(function()
	if next(RideManager.Rides) == nil and next(lastPos) == nil then return end
	local seen = {}
	for _, ride in pairs(RideManager.Rides) do
		seen[ride] = true
		local chassis = ride.Scooter and ride.Scooter.PrimaryPart
		if chassis and not ride._ended then
			local pos, prev = chassis.Position, lastPos[ride]
			lastPos[ride] = pos
			if prev and pos ~= prev and (pos - prev).Magnitude <= MAX_STEP then
				for _, gate in ipairs(CollectionService:GetTagged(FINISH_TAG)) do
					if gate:IsA("BasePart") and crossed(gate, prev, pos) then
						funnel("RideFinished", ride)   -- analytics only
						unlock(ride.Driver)
						unlock(ride.Passenger)
						break
					end
				end
			end
		end
	end
	for ride in pairs(lastPos) do
		if not seen[ride] then lastPos[ride] = nil end
	end
end)

-- backup: every run RunTimer saw finish
task.spawn(function()
	local rt = ScooterSystem:WaitForChild("RunTimer", 30)
	local ev = rt and rt:WaitForChild("RunCompleted", 30)
	if not ev then return end
	ev.Event:Connect(function(record)
		for _, p in ipairs({ record.Player1 or false, record.Player2 or false }) do
			if p and p.UserId then unlock(Players:GetPlayerByUserId(p.UserId)) end
		end
	end)
end)
