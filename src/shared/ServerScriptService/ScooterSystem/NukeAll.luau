--=====================================================================
-- NukeAll   (ScooterSystem, server) - NUKE ALL, bought at the Nuke Podium
--
-- The Nuke Podium (Workspace."Nuke Podium", on the lobby's podium shop base) has a normal E
-- prompt (tagged "NukeShopPrompt"). Pressing it opens Roblox's purchase window for
-- Config.NukeAllProductId; 0 = not set up yet, and it only says it's coming soon. Roblox's
-- receipt (DonationHandler's ProcessReceipt hands it here) is the only thing that starts it.
--
-- What it DOES is NukeAll.Run(buyer), on one clock (ReplicatedStorage.TrollFx.NukeTimeline):
--   everyone   Remotes.NukeAlert { By, Start } to every player: each one's own cinematic
--              (StarterGui.NukeGui.NukeCinematic) - whole map, the nuke close up, the fall,
--              the explosion - with every other screen of theirs put away. It is ONLY a
--              picture: nothing about the map is ever touched.
--   the rides  every ride out on the course is taken (DeathManager.Claim, as a troll takes
--              one) and plays the shared troll show on the same clock (ScooterSystem.TrollShow,
--              quiet: no troll banner, the cinematic is their show) - the run is over for good,
--              the scooter stops dead, is gone in the explosion, and at the end the ride goes
--              down as an obstacle's would: the death popup, SKIP / REVIVE, exactly as always.
--   the lobby  at the end, everyone on foot (not on a ride, not in a booth) goes down and is
--              brought back by the game's own respawn (ScooterSystem.Main).
-- One nuke at a time: a second one bought meanwhile waits for the first to finish.
--
-- The same global show is shared: NukeAll.RunShow(show, buyer) plays any whole-server show on
-- its own clock (ScooterSystem.LavaDragon's LAVA DRAGON). Only one global show plays at a time.
--=====================================================================

local RideManager  = require(script.Parent:WaitForChild("RideManager"))
local DeathManager = require(script.Parent:WaitForChild("DeathManager"))
local TeamManager  = require(script.Parent:WaitForChild("TeamManager"))
local TrollShow    = require(script.Parent:WaitForChild("TrollShow"))
local TrollWebhook = require(script.Parent:WaitForChild("TrollWebhook"))

local Players            = game:GetService("Players")
local CollectionService  = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS                 = game:GetService("ReplicatedStorage")

local Root    = RS:WaitForChild("ScooterSystem")
local Remotes = Root:WaitForChild("Remotes")

-- Who is fully in the game: their loading screen (and World 1's first-join intro) has handed
-- them control - their own machine says so once (NukeGui.NukeCinematic, Remotes.PlayerReady).
-- Anyone not yet in is never knocked down by a show's end. (It only ever spares a player.)
local ready = {}
local readyRemote = Remotes:FindFirstChild("PlayerReady")
if not readyRemote then
	readyRemote = Instance.new("RemoteEvent")
	readyRemote.Name = "PlayerReady"
	readyRemote.Parent = Remotes
end
readyRemote.OnServerEvent:Connect(function(player) ready[player] = true end)
Players.PlayerRemoving:Connect(function(player) ready[player] = nil end)
local Config  = require(Root:WaitForChild("Shared"):WaitForChild("Config"))

local PRODUCT     = Config.NukeAllProductId or 0
local PROMPT_TAG  = "NukeShopPrompt"
local ASK_GAP     = 1          -- seconds between one player's presses
local SOON_NOTE   = "Nuke All is coming soon!"
local Timeline    = require(RS:WaitForChild("TrollFx"):WaitForChild("NukeTimeline"))
local DEF         = { Id = "Nuke", Name = "Nuke All", Emoji = "\u{2622}\u{FE0F}" }   -- for the troll log
-- the nuke as a global show: its log entry, its clock, the remote every player's cinematic
-- listens on, and why the run ended (RunTimer, the log)
local NUKE_SHOW   = { Def = DEF, Timeline = Timeline, Alert = Remotes:WaitForChild("NukeAlert"), Why = "nuked (Nuke All)" }

local NukeAll = {}

local function log(...) if Config.DebugLogging then print("[NukeAll]", ...) end end

---------------------------------------------------------------- what it does
local busyUntil = 0   -- server time the global show playing now is over

local function ridersOf(ride)
	local list = {}
	for _, p in ipairs({ ride.Driver, ride.Passenger }) do
		if typeof(p) == "Instance" and p:IsA("Player") then table.insert(list, p) end
	end
	return list
end

-- one ride, taken by the show: the shared troll show on the show's clock
local function takeRide(ride, buyer, start, show)
	local life = DeathManager.Claim(ride)   -- nothing else can take it now (or it was already going down)
	if not life then return false end
	ride.Troll = { Effect = show.Def.Id, Buyer = buyer }
	ride.TrollShow = true
	local ctx = {
		Def = show.Def, Ride = ride, Scooter = ride.Scooter, Life = life, Buyer = buyer,
		BuyerName = buyer and buyer.DisplayName or "Someone", Riders = ridersOf(ride),
	}
	task.spawn(function()
		local ok, err = pcall(TrollShow.Play, ctx, show.Def.Id, show.Timeline, show.Why, { Start = start, Quiet = true })
		if not ok then warn("[NukeAll] " .. tostring(err)) end
		ride.TrollShow = nil
		ride.Troll = nil
		-- never left taken: ended as the popup's own timer would end it
		if not ok and not ride._ended and not ride.Down then DeathManager.Finish(ride, show.Why) end
	end)
	return true
end

-- A whole-server show, bought and paid for: the cinematic for everyone (show.Alert), every
-- ride down, the lobby down. show = { Def, Timeline, Alert, Why }. Returns how many rides it took.
function NukeAll.RunShow(show, buyer)
	local Timeline = show.Timeline
	-- one at a time
	while workspace:GetServerTimeNow() < busyUntil do task.wait(0.25) end
	local start = workspace:GetServerTimeNow() + Timeline.LEAD
	busyUntil = start + Timeline.END + 1
	log(buyer and buyer.Name or "?", "played", show.Def.Name, "on everyone")
	show.Alert:FireAllClients({ By = buyer and buyer.DisplayName or "Someone", Start = start })

	local rides = 0
	for _, ride in pairs(RideManager.Rides) do
		if takeRide(ride, buyer, start, show) then rides += 1 end
	end

	-- the lobby: at the end, everyone on foot goes down (not players still loading in) (the game's own respawn brings them back)
	task.delay(math.max(start + Timeline.END - workspace:GetServerTimeNow(), 0), function()
		for _, plr in ipairs(Players:GetPlayers()) do
			if ready[plr] and not RideManager.PlayerRide[plr] and not TeamManager.FindSlot(plr) then
				local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then hum.Health = 0 end
			end
		end
	end)
	return rides
end

-- Bought and paid for: the nuke for everyone. Returns how many rides it took.
function NukeAll.Run(buyer)
	return NukeAll.RunShow(NUKE_SHOW, buyer)
end

---------------------------------------------------------------- the prompt
local lastAsk = {}
Players.PlayerRemoving:Connect(function(player) lastAsk[player] = nil end)

local function pressed(player)
	local now = os.clock()
	if now - (lastAsk[player] or 0) < ASK_GAP then return end
	lastAsk[player] = now
	if PRODUCT == 0 then
		Remotes.Notice:FireClient(player, SOON_NOTE)
		return
	end
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, PRODUCT)
	if not ok then warn("[NukeAll] couldn't open the purchase for " .. player.Name .. ": " .. tostring(err)) end
end

local wired = setmetatable({}, { __mode = "k" })
local function wire(prompt)
	if wired[prompt] or not prompt:IsA("ProximityPrompt") then return end
	wired[prompt] = true
	prompt.Triggered:Connect(pressed)
end
for _, p in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do wire(p) end
CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(wire)

---------------------------------------------------------------- buying (Roblox's receipt)
local handled = {}   -- [PurchaseId] = true

function NukeAll.IsProduct(productId)
	return PRODUCT ~= 0 and productId == PRODUCT
end

function NukeAll.ProcessReceipt(receipt)
	local id = tostring(receipt.PurchaseId)
	if handled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if not buyer then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	handled[id] = true
	task.spawn(function()
		local ok, rides = pcall(NukeAll.Run, buyer)
		if not ok then warn("[NukeAll] " .. tostring(rides)) return end
		pcall(TrollWebhook.Log, DEF, receipt, ("Nuked the whole map (%d duo%s out riding)"):format(rides, rides == 1 and "" or "s"), nil)
	end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- studio
-- Studio only, never in a live server. From the command bar while testing (Server view):
--   game.ServerStorage.NukeStudioTest:Invoke(player)   play it now, as if they'd bought it (no log)
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "NukeStudioTest"
	hook.OnInvoke = function(player)
		task.spawn(NukeAll.Run, player)
		return true
	end
	hook.Parent = game:GetService("ServerStorage")
end

return NukeAll
