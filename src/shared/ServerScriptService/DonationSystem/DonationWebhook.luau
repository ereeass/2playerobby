--=====================================================================
-- DonationSystem / DonationWebhook
--
-- A log of donations for the team's Discord: who donated, the Robux they paid and what we
-- keep after Roblox's 30% cut. DonationHandler calls Log once a donation is saved and
-- granted; it runs in the background and never touches the purchase or tells the buyer
-- anything. If Discord can't be reached it tries a couple more times, then gives up (the
-- donation itself is already safe). The webhook lives only here on the server.
-- Needs Game Settings > Security > Allow HTTP Requests.
--=====================================================================

-- which world (place) this came from (ReplicatedStorage.WorldConfig: "World 1", "World 2"...),
-- on the end of every title, the same way the bug reports say it
local WORLD = (function()
	local ok, cfg = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig", 10)) end)
	return ok and cfg and cfg.Name or ("Place " .. game.PlaceId)
end)()

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")

local WEBHOOK  = "https://webhook-relay.jaihoadam12.workers.dev/api/webhooks/1553997171936727042/Tz3MceADLTN97o3TGlQ7NK3aDF4zkbRFr7y-8ijTM7xeI6X4f3I4xtiJqypCEFlMAc3O?key=8Rdasfa9SDHsd89238wefhADFSJF3jas2"
local KEEP     = 0.7     -- what we keep: Roblox takes 30% of developer product sales
local TRIES    = 3

local DonationWebhook = {}

local logged = {}        -- [PurchaseId] = true: one message per purchase on this server

local function commas(n)
	local s = tostring(math.floor(n))
	repeat
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

function DonationWebhook.Log(userId, amount, purchaseId)
	if purchaseId then
		if logged[purchaseId] then return end
		logged[purchaseId] = true
	end
	task.spawn(function()
		local player = Players:GetPlayerByUserId(userId)
		local who
		if player then
			who = ("%s (@%s)"):format(player.DisplayName, player.Name)
		else
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			who = ok and ("@" .. name) or "Unknown player"
		end
		local earned = math.floor(amount * KEEP)
		local body = HttpService:JSONEncode({
			username = "Donations",
			allowed_mentions = { parse = {} },
			embeds = { {
				title = (RunService:IsStudio() and "[Studio test] " or "") .. "New donation - " .. WORLD,
				color = 0xFFCD40,
				fields = {
					{ name = "Player", value = ("%s\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d"):format(who, userId, userId), inline = false },
					{ name = "Paid", value = commas(amount) .. " Robux", inline = true },
					{ name = "We earn (after 30%)", value = commas(earned) .. " Robux", inline = true },
				},
				footer = { text = "Purchase " .. tostring(purchaseId or "?") },
				timestamp = DateTime.now():ToIsoDate(),
			} },
		})
		for try = 1, TRIES do
			local ok, err = pcall(HttpService.PostAsync, HttpService, WEBHOOK, body, Enum.HttpContentType.ApplicationJson)
			if ok then
				print(("[DonationWebhook] logged %d Robux from %s"):format(amount, who))
				return
			end
			if try == TRIES then
				warn("[DonationWebhook] couldn't log a donation: " .. tostring(err))
			else
				task.wait(5 * try)
			end
		end
	end)
end

return DonationWebhook
