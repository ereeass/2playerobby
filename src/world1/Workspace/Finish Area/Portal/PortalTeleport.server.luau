-- A World portal. Set the PlaceId attribute on this Portal model to the place to send players
-- to (a place in this experience); while it's 0 the portal does nothing.
--
-- Locked until the player has the unlock in this portal's RequiresUnlock attribute (a Player
-- attribute saved by ServerScriptService.WorldUnlock, e.g. BeatWorld1; "" or none = open to
-- everyone). Checked here on the server: pressing E while it's locked only shows the red
-- notice at the bottom (Remotes.Notice: this portal's LockedNote attribute).
--
-- Entering: the ProximityPrompt on PortalTrigger (press E). With the attribute
-- TouchToEnter = true, walking or driving into the portal works as well.
-- A scooter pair goes together (TeleportAsync with both riders) so they arrive in the same
-- server - as long as both have unlocked it; otherwise only the ones who have go.
-- Teleports only work in a live game (not in Studio).

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))

local DEFAULT_NOTE = "You haven't unlocked this world yet"   -- the red notice at the bottom, if no LockedNote is set
local NOTE_GAP    = 1                                  -- seconds between one player's notices
local Remotes     = game:GetService("ReplicatedStorage"):WaitForChild("ScooterSystem"):WaitForChild("Remotes")

local portal  = script.Parent
local trigger = portal:WaitForChild("PortalTrigger")
local prompt  = trigger:WaitForChild("WorldPrompt")
local sending = {}   -- [player] = true while their teleport is on its way

-- the unlock this portal needs (its RequiresUnlock attribute; none = open to everyone)
local function unlocked(plr)
	local need = portal:GetAttribute("RequiresUnlock")
	if type(need) ~= "string" or need == "" then return plr ~= nil end
	return plr and plr:GetAttribute(need) == true
end

-- the player and, if they are riding, their partner
local function groupOf(plr)
	local ride = RideManager.PlayerRide[plr]
	if ride then return { ride.Driver, ride.Passenger } end
	return { plr }
end

local function playerFromHit(hit)
	for scooter, ride in pairs(RideManager.Rides) do
		if hit:IsDescendantOf(scooter) then return ride.Driver or ride.Passenger end
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then return plr end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function send(plr)
	if not unlocked(plr) then return end
	local placeId = portal:GetAttribute("PlaceId") or 0
	if placeId == 0 then return end
	local go = {}
	for _, p in ipairs(groupOf(plr)) do
		if p and p.Parent == Players and unlocked(p) and not sending[p] then
			sending[p] = true
			table.insert(go, p)
		end
	end
	if #go == 0 then return end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, go, Instance.new("TeleportOptions"))
	end)
	if not ok then
		warn("[Portal] teleport failed: " .. tostring(err))
		for _, p in ipairs(go) do sending[p] = nil end
	end
end

-- pressing E: in, or (still locked) the red notice at the bottom saying how to unlock it
local lastNote = {}
prompt.Triggered:Connect(function(plr)
	if unlocked(plr) then send(plr) return end
	local now = os.clock()
	if now - (lastNote[plr] or 0) < NOTE_GAP then return end
	lastNote[plr] = now
	Remotes.Notice:FireClient(plr, portal:GetAttribute("LockedNote") or DEFAULT_NOTE)
end)

trigger.Touched:Connect(function(hit)
	if portal:GetAttribute("TouchToEnter") ~= true then return end
	local plr = playerFromHit(hit)
	if plr then send(plr) end
end)

TeleportService.TeleportInitFailed:Connect(function(plr) sending[plr] = nil end)
Players.PlayerRemoving:Connect(function(plr) sending[plr] = nil; lastNote[plr] = nil end)
