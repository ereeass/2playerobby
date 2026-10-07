--=====================================================================
-- ScooterSystem / ReviveWebhook
--
-- A log of Revive sales for the team's Discord, as SkipStageWebhook logs Skip Stage: who
-- bought it, who they revived with, the Robux they paid, what we keep after Roblox's 30% cut,
-- and what it did (revived the ride, or saved as a free revive). DeathManager calls Log once a
-- purchase is granted; it runs in the background and never touches the purchase or tells the
-- buyer anything. The webhook lives only here. Needs Game Settings > Security > Allow HTTP
-- Requests.
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

local WEBHOOK = "https://webhook-relay.jaihoadam12.workers.dev/api/webhooks/1554375688302104650/_LZvP5e54AfmRXBK6M2NZcE-u698f3FhjaWaaWlsszwPlMf0uMrKNcuFat6wMy8gllui?key=8Rdasfa9SDHsd89238wefhADFSJF3jas2"
local KEEP    = 0.7      -- what we keep: Roblox takes 30% of developer product sales
local TRIES   = 3

local ReviveWebhook = {}

local logged = {}        -- [PurchaseId] = true: one message per purchase on this server
local listPrice          -- the product's price, for Studio test buys (which cost 0)

local function commas(n)
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

-- outcome: e.g. "Revived the ride" or "Saved as a free revive"; partner: the other rider's
-- name, or nil
function ReviveWebhook.Log(receipt, outcome, partner)
	if logged[receipt.PurchaseId] then return end
	logged[receipt.PurchaseId] = true
	task.spawn(function()
		local userId = receipt.PlayerId
		local player = Players:GetPlayerByUserId(userId)
		local who
		if player then
			who = ("%s (@%s)"):format(player.DisplayName, player.Name)
		else
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			who = ok and ("@" .. name) or "Unknown player"
		end
		local price = tonumber(receipt.CurrencySpent) or 0
		if price <= 0 then
			if not listPrice then
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, receipt.ProductId, Enum.InfoType.Product)
				listPrice = ok and info and tonumber(info.PriceInRobux) or 0
			end
			price = listPrice
		end
		local fields = {
			{ name = "Player", value = ("%s\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d"):format(who, userId, userId), inline = false },
			{ name = "What happened", value = outcome, inline = false },
		}
		if partner then table.insert(fields, { name = "Duo partner", value = partner, inline = false }) end
		table.insert(fields, { name = "Paid", value = commas(price) .. " Robux", inline = true })
		table.insert(fields, { name = "We earn (after 30%)", value = commas(price * KEEP) .. " Robux", inline = true })
		local body = HttpService:JSONEncode({
			username = "Revive Sales",
			allowed_mentions = { parse = {} },
			embeds = { {
				title = (RunService:IsStudio() and "[Studio test] " or "") .. "Revive bought - " .. WORLD,
				color = 0x3CC864,
				fields = fields,
				footer = { text = "Purchase " .. tostring(receipt.PurchaseId) },
				timestamp = DateTime.now():ToIsoDate(),
			} },
		})
		for try = 1, TRIES do
			local ok, err = pcall(HttpService.PostAsync, HttpService, WEBHOOK, body, Enum.HttpContentType.ApplicationJson)
			if ok then
				print(("[ReviveWebhook] logged a Revive from %s (%s)"):format(who, outcome))
				return
			end
			if try == TRIES then
				warn("[ReviveWebhook] couldn't log a Revive sale: " .. tostring(err))
			else
				task.wait(5 * try)
			end
		end
	end)
end

return ReviveWebhook
