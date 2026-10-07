--=====================================================================
-- ScooterSystem / ScooterWebhook
--
-- A log of scooter sales for the team's Discord: who bought which scooter, the Robux they
-- paid and what we keep after Roblox's 30% cut. Runs in the background; never touches the
-- purchase or tells the buyer anything. The webhook lives only here on the server.
--
-- Every scooter in ReplicatedStorage.ScooterSystem.Shared.Scooters is covered on its own,
-- including ones added later - nothing to change here:
--   Unlock.Type "Product"   DonationHandler calls LogProduct once the unlock is saved
--   Unlock.Type "GamePass"  bought in the game (PromptGamePassPurchaseFinished, below)
-- (a pass bought on the website instead of in the game isn't seen by any server)
-- Needs Game Settings > Security > Allow HTTP Requests.
--=====================================================================

-- which world (place) this came from (ReplicatedStorage.WorldConfig: "World 1", "World 2"...),
-- on the end of every title, the same way the bug reports say it
local WORLD = (function()
	local ok, cfg = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig", 10)) end)
	return ok and cfg and cfg.Name or ("Place " .. game.PlaceId)
end)()

local Players            = game:GetService("Players")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Scooters = require(ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Scooters"))

local WEBHOOK = "https://webhook-relay.jaihoadam12.workers.dev/api/webhooks/1554000493699661890/y1Ujg2XYwNWNDOeszPidkly3Lb0CZPT2svM04Yorbw2k4uyllX5lL6eWMSuQedc-H02Q?key=8Rdasfa9SDHsd89238wefhADFSJF3jas2"
local KEEP    = 0.7      -- what we keep: Roblox takes 30% of sales
local TRIES   = 3

local ScooterWebhook = {}

-- the scooter a product / pass unlocks, looked up fresh each time (so new scooters count)
local function scooterFor(kind, id)
	for _, def in ipairs(Scooters.List or {}) do
		local u = def.Unlock
		if u and u.Type == kind and (u.ProductId == id or u.GamePassId == id) then return def end
	end
	return nil
end

local function commas(n)
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

local function post(userId, def, price, how, ref, giftTo)
	task.spawn(function()
		local player = Players:GetPlayerByUserId(userId)
		local who
		if player then
			who = ("%s (@%s)"):format(player.DisplayName, player.Name)
		else
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			who = ok and ("@" .. name) or "Unknown player"
		end
		local scooter = def and ((def.DisplayName or def.Id) .. " (" .. tostring(def.Id) .. ")") or "Unknown scooter"
		local fields = {
			{ name = "Player", value = ("%s\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d"):format(who, userId, userId), inline = false },
			{ name = "Scooter", value = scooter, inline = false },
		}
		if giftTo then
			local to = Players:GetPlayerByUserId(giftTo)
			local ok, name = true, to and (to.DisplayName .. " (@" .. to.Name .. ")")
			if not name then ok, name = pcall(Players.GetNameFromUserIdAsync, Players, giftTo) name = ok and ("@" .. name) or "Unknown player" end
			table.insert(fields, { name = "Gifted to", value = ("%s\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d"):format(name, giftTo, giftTo), inline = false })
		end
		if price and price > 0 then
			table.insert(fields, { name = "Paid", value = commas(price) .. " Robux", inline = true })
			table.insert(fields, { name = "We earn (after 30%)", value = commas(price * KEEP) .. " Robux", inline = true })
		else
			table.insert(fields, { name = "Paid", value = "unknown", inline = true })
		end
		local body = HttpService:JSONEncode({
			username = "Scooter Sales",
			allowed_mentions = { parse = {} },
			embeds = { {
				title = (RunService:IsStudio() and "[Studio test] " or "") .. (giftTo and "Scooter gifted - " or "Scooter bought - ") .. WORLD,
				color = 0x4CC458,
				fields = fields,
				footer = { text = how .. " " .. tostring(ref) },
				timestamp = DateTime.now():ToIsoDate(),
			} },
		})
		for try = 1, TRIES do
			local ok, err = pcall(HttpService.PostAsync, HttpService, WEBHOOK, body, Enum.HttpContentType.ApplicationJson)
			if ok then
				print(("[ScooterWebhook] logged %s bought by %s"):format(scooter, who))
				return
			end
			if try == TRIES then
				warn("[ScooterWebhook] couldn't log a scooter sale: " .. tostring(err))
			else
				task.wait(5 * try)
			end
		end
	end)
end

-- a developer-product scooter, once its unlock is saved (DonationHandler's ProcessReceipt)
local loggedReceipts = {}
function ScooterWebhook.LogProduct(receipt)
	if loggedReceipts[receipt.PurchaseId] then return end
	loggedReceipts[receipt.PurchaseId] = true
	local def = scooterFor("Product", receipt.ProductId)
	local price = tonumber(receipt.CurrencySpent) or 0
	if price <= 0 and def then price = tonumber(def.Unlock.Price) or 0 end   -- Studio test buys cost 0
	post(receipt.PlayerId, def, price, "Purchase", receipt.PurchaseId)
end

-- a scooter bought as a gift for another player (ScooterSystem.Gifting), once it is saved
function ScooterWebhook.LogGift(receipt, def, toUserId)
	if loggedReceipts[receipt.PurchaseId] then return end
	loggedReceipts[receipt.PurchaseId] = true
	local price = tonumber(receipt.CurrencySpent) or 0
	if price <= 0 and def then price = tonumber(def.Unlock.Price) or 0 end
	post(receipt.PlayerId, def, price, "Gift", receipt.PurchaseId, toUserId)
end

-- a crate opened in the Shop (ScooterSystem.Crates), once its prize is saved: the scooter it
-- gave (bonus: it was a duplicate and gave that instead; toUserId: a gift, who it went to -
-- def nil when it went to someone not in the server)
function ScooterWebhook.LogCrate(receipt, def, crate, bonus, toUserId)
	if loggedReceipts[receipt.PurchaseId] then return end
	loggedReceipts[receipt.PurchaseId] = true
	local price = tonumber(receipt.CurrencySpent) or 0
	if price <= 0 and crate then price = tonumber(crate.Price) or 0 end
	local how = (crate and crate.Name or "Crate") .. (bonus and (" (duplicate - gave " .. bonus .. ")") or "")
	post(receipt.PlayerId, def, price, how, receipt.PurchaseId, toUserId)
end

-- a game-pass scooter bought in the game
local loggedPasses = {}
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if not bought then return end
	local def = scooterFor("GamePass", passId)
	if not def then return end   -- some other game pass
	local key = player.UserId .. ":" .. passId
	if loggedPasses[key] then return end
	loggedPasses[key] = true
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, passId, Enum.InfoType.GamePass)
		local price = ok and info and tonumber(info.PriceInRobux) or tonumber(def.Unlock.Price) or 0
		post(player.UserId, def, price, "Game pass", passId)
	end)
end)

return ScooterWebhook
