--=====================================================================
-- LavaDragon   (ScooterSystem, server) - LAVA DRAGON, bought at the Lava Dragon Podium
--
-- The Lava Dragon Podium (Workspace."Lava Dragon Podium", next to the Nuke Podium) has a normal
-- E prompt (tagged "DragonShopPrompt"). Pressing it opens Roblox's purchase window for
-- Config.LavaDragonProductId; 0 = not set up yet, and it only says it's coming soon. Roblox's
-- receipt (DonationHandler's ProcessReceipt hands it here) is the only thing that starts it.
--
-- It is the same global show as NUKE ALL (ScooterSystem.NukeAll.RunShow), on its own clock
-- (ReplicatedStorage.TrollFx.DragonTimeline):
--   everyone   Remotes.DragonAlert { By, Start } to every player: each one's own cinematic
--              (StarterGui.DragonGui.DragonCinematic) - the dragon rising out of the sea, its
--              roar, its flight down the whole course breathing fire, the fireball - with every
--              other screen of theirs put away. It is ONLY a picture: the map is never touched.
--   the rides  every ride out on the course goes down at the end, SKIP / REVIVE as always.
--   the lobby  at the end, everyone on foot goes down and respawns.
-- One global show at a time (a nuke and a dragon never play together).
--=====================================================================

local NukeAll      = require(script.Parent:WaitForChild("NukeAll"))
local TrollWebhook = require(script.Parent:WaitForChild("TrollWebhook"))

local Players            = game:GetService("Players")
local CollectionService  = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS                 = game:GetService("ReplicatedStorage")

local Root    = RS:WaitForChild("ScooterSystem")
local Remotes = Root:WaitForChild("Remotes")
local Config  = require(Root:WaitForChild("Shared"):WaitForChild("Config"))

local PRODUCT    = Config.LavaDragonProductId or 0
local PROMPT_TAG = "DragonShopPrompt"
local ASK_GAP    = 1          -- seconds between one player's presses
local SOON_NOTE  = "The Lava Dragon is coming soon!"
local DEF        = { Id = "Dragon", Name = "Lava Dragon", Emoji = "\u{1F409}" }   -- for the troll log
local SHOW = {
	Def = DEF,
	Timeline = require(RS:WaitForChild("TrollFx"):WaitForChild("DragonTimeline")),
	Alert = Remotes:WaitForChild("DragonAlert"),
	Why = "burned (Lava Dragon)",
}

local LavaDragon = {}

-- Bought and paid for: the dragon for everyone. Returns how many rides it took.
function LavaDragon.Run(buyer)
	return NukeAll.RunShow(SHOW, buyer)
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
	if not ok then warn("[LavaDragon] couldn't open the purchase for " .. player.Name .. ": " .. tostring(err)) end
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

function LavaDragon.IsProduct(productId)
	return PRODUCT ~= 0 and productId == PRODUCT
end

function LavaDragon.ProcessReceipt(receipt)
	local id = tostring(receipt.PurchaseId)
	if handled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if not buyer then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	handled[id] = true
	task.spawn(function()
		local ok, rides = pcall(LavaDragon.Run, buyer)
		if not ok then warn("[LavaDragon] " .. tostring(rides)) return end
		pcall(TrollWebhook.Log, DEF, receipt, ("Unleashed the Lava Dragon on the whole map (%d duo%s out riding)"):format(rides, rides == 1 and "" or "s"), nil)
	end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- studio
-- Studio only, never in a live server. From the command bar while testing (Server view):
--   game.ServerStorage.DragonStudioTest:Invoke(player)   play it now, as if they'd bought it (no log)
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "DragonStudioTest"
	hook.OnInvoke = function(player)
		task.spawn(LavaDragon.Run, player)
		return true
	end
	hook.Parent = game:GetService("ServerStorage")
end

return LavaDragon
