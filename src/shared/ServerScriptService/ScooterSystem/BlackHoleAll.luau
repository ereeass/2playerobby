--=====================================================================
-- BlackHoleAll   (ScooterSystem, server) - BLACK HOLE - KILL ALL, bought at the Black Hole Podium
--
-- The Black Hole Podium (Workspace."Black Hole Podium", on the podium shop base next to the Nuke
-- Podium) has a normal E prompt (tagged "BlackHoleShopPrompt"). Pressing it opens Roblox's
-- purchase window for Config.BlackHoleAllProductId; 0 = not set up yet, and it only says it's
-- coming soon. Roblox's receipt (DonationHandler's ProcessReceipt hands it here) is the only
-- thing that starts it.
--
-- It is the same global show as NUKE ALL and the LAVA DRAGON (ScooterSystem.NukeAll.RunShow),
-- on its own clock (ReplicatedStorage.TrollFx.BlackHoleAllTimeline):
--   everyone   Remotes.BlackHoleAllAlert { By, Start } to every player: each one's own cinematic
--              (StarterGui.BlackHoleAllGui.BlackHoleAllCinematic) - a black hole tearing open
--              high over the map, pulling everything in, caving in on itself, the burst - with
--              every other screen of theirs put away. It is ONLY a picture: the map is never touched.
--   the rides  every ride out on the course goes down at the end, SKIP / REVIVE as always.
--   the lobby  at the end, everyone on foot goes down and respawns.
-- One global show at a time (a nuke, a dragon and a black hole never play together).
-- Not the troll menu's BLACK HOLE (TrollEffects, "BlackHole"), which swallows one duo: this one
-- is "BlackHoleAll" everywhere in the code.
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

local PRODUCT    = Config.BlackHoleAllProductId or 0
local PROMPT_TAG = "BlackHoleShopPrompt"
local ASK_GAP    = 1          -- seconds between one player's presses
local SOON_NOTE  = "The Black Hole is coming soon!"
local DEF        = { Id = "BlackHoleAll", Name = "Black Hole - Kill All", Emoji = "\u{1F573}\u{FE0F}" }   -- for the troll log
local SHOW = {
	Def = DEF,
	Timeline = require(RS:WaitForChild("TrollFx"):WaitForChild("BlackHoleAllTimeline")),
	Alert = Remotes:WaitForChild("BlackHoleAllAlert"),
	Why = "swallowed (Black Hole)",
}

local BlackHoleAll = {}

-- Bought and paid for: the black hole for everyone. Returns how many rides it took.
function BlackHoleAll.Run(buyer)
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
	if not ok then warn("[BlackHoleAll] couldn't open the purchase for " .. player.Name .. ": " .. tostring(err)) end
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

function BlackHoleAll.IsProduct(productId)
	return PRODUCT ~= 0 and productId == PRODUCT
end

function BlackHoleAll.ProcessReceipt(receipt)
	local id = tostring(receipt.PurchaseId)
	if handled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if not buyer then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	handled[id] = true
	task.spawn(function()
		local ok, rides = pcall(BlackHoleAll.Run, buyer)
		if not ok then warn("[BlackHoleAll] " .. tostring(rides)) return end
		pcall(TrollWebhook.Log, DEF, receipt, ("Swallowed the whole map in a Black Hole (%d duo%s out riding)"):format(rides, rides == 1 and "" or "s"), nil)
	end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- studio
-- Studio only, never in a live server. From the command bar while testing (Server view):
--   game.ServerStorage.BlackHoleAllStudioTest:Invoke(player)   play it now, as if they'd bought it (no log)
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "BlackHoleAllStudioTest"
	hook.OnInvoke = function(player)
		task.spawn(BlackHoleAll.Run, player)
		return true
	end
	hook.Parent = game:GetService("ServerStorage")
end

return BlackHoleAll
