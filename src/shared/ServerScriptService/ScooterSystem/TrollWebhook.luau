--=====================================================================
-- ScooterSystem / TrollWebhook
--
-- A log of Troll sales for the team's Discord: who bought which troll, on which duo, the Robux
-- they paid, what we keep after Roblox's 30% cut, and what became of it. EVERY troll in
-- ReplicatedStorage.TrollFx.Effects is logged here by itself - its name and emoji come from
-- there - so a new troll needs nothing added to this file.
--   Log(def, receipt, outcome, trolled)   a purchase, once per PurchaseId (TrollEffects calls
--                                         it once the purchase is granted)
--   Note(def, buyer, outcome, trolled)    something after it with no Robux in it: a saved free
--                                         one spent, or one given back because the duo left
-- Both run in the background and never touch the purchase or tell anyone anything. The
-- webhook address lives only here, on the server. Needs Game Settings > Security > Allow
-- HTTP Requests.
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

local WEBHOOK = "https://webhook-relay.jaihoadam12.workers.dev/api/webhooks/1554106463478353963/xeCAsF5ZFN9PkbbOGlUFwZpCo3CBfAHBpKjpDjCPDbolgxBYNxuNHmpPvNi3QpU1G33p?key=8Rdasfa9SDHsd89238wefhADFSJF3jas2"
local KEEP    = 0.7      -- what we keep: Roblox takes 30% of developer product sales
local TRIES   = 3
local COLOR_SALE, COLOR_NOTE = 0xE8484F, 0x58A6F0

local TrollWebhook = {}

local logged = {}        -- [PurchaseId] = true: one message per purchase on this server
local listPrice = {}     -- [ProductId] = its price, for Studio test buys (which cost 0)

local function commas(n)
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

local function whoIs(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player then return ("%s (@%s)"):format(player.DisplayName, player.Name) end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return ok and ("@" .. name) or "Unknown player"
end

local function title(def, what)
	return (RunService:IsStudio() and "[Studio test] " or "") .. (def.Emoji and (def.Emoji .. " ") or "") .. def.Name .. " " .. what .. " - " .. WORLD
end

local function post(body, what)
	for try = 1, TRIES do
		local ok, err = pcall(HttpService.PostAsync, HttpService, WEBHOOK, body, Enum.HttpContentType.ApplicationJson)
		if ok then
			print("[TrollWebhook] logged " .. what)
			return
		end
		if try == TRIES then
			warn("[TrollWebhook] couldn't log " .. what .. ": " .. tostring(err))
		else
			task.wait(5 * try)
		end
	end
end

-- outcome: e.g. "Launched!" or "Saved as a free Rocket Launch"; trolled: "A & B" (or nil)
function TrollWebhook.Log(def, receipt, outcome, trolled)
	if logged[receipt.PurchaseId] then return end
	logged[receipt.PurchaseId] = true
	task.spawn(function()
		local userId = receipt.PlayerId
		local who = whoIs(userId)
		local price = tonumber(receipt.CurrencySpent) or 0
		if price <= 0 then
			if listPrice[receipt.ProductId] == nil then
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, receipt.ProductId, Enum.InfoType.Product)
				listPrice[receipt.ProductId] = ok and info and tonumber(info.PriceInRobux) or 0
			end
			price = listPrice[receipt.ProductId]
		end
		local fields = {
			{ name = "Bought by", value = ("%s\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d"):format(who, userId, userId), inline = false },
		}
		if trolled then table.insert(fields, { name = "Trolled", value = trolled, inline = false }) end
		table.insert(fields, { name = "What happened", value = outcome, inline = false })
		table.insert(fields, { name = "Paid", value = commas(price) .. " Robux", inline = true })
		table.insert(fields, { name = "We earn (after 30%)", value = commas(price * KEEP) .. " Robux", inline = true })
		post(HttpService:JSONEncode({
			username = "Troll Sales",
			allowed_mentions = { parse = {} },
			embeds = { {
				title = title(def, "bought"),
				color = COLOR_SALE,
				fields = fields,
				footer = { text = "Purchase " .. tostring(receipt.PurchaseId) },
				timestamp = DateTime.now():ToIsoDate(),
			} },
		}), ("a %s from %s (%s)"):format(def.Name, who, outcome))
	end)
end

-- buyer: the Player (or their UserId)
function TrollWebhook.Note(def, buyer, outcome, trolled)
	task.spawn(function()
		local userId = typeof(buyer) == "Instance" and buyer.UserId or tonumber(buyer) or 0
		local who = whoIs(userId)
		local fields = {
			{ name = "Player", value = ("%s\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d"):format(who, userId, userId), inline = false },
		}
		if trolled then table.insert(fields, { name = "Trolled", value = trolled, inline = false }) end
		table.insert(fields, { name = "What happened", value = outcome, inline = false })
		post(HttpService:JSONEncode({
			username = "Troll Sales",
			allowed_mentions = { parse = {} },
			embeds = { {
				title = title(def, "(no Robux)"),
				color = COLOR_NOTE,
				fields = fields,
				timestamp = DateTime.now():ToIsoDate(),
			} },
		}), ("a %s note for %s (%s)"):format(def.Name, who, outcome))
	end)
end

return TrollWebhook
