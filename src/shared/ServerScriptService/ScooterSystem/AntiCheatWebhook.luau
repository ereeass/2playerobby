--=====================================================================
-- ScooterSystem / AntiCheatWebhook
--
-- AntiCheat's reports for the team's Discord: who, their UserId, which server, what
-- happened, what was done about it, and how sure the anti-cheat is (a percentage).
--   Report(player, info)   info = { What, Detail, Action, Certainty (0-100), Partner }
-- Runs in the background and never affects the game. Kept quiet: one message per player per
-- kind of violation per COOLDOWN seconds, and at most SERVER_PER_MINUTE a minute per server.
-- The webhook address lives only here, on the server (Game Settings > Security > Allow HTTP
-- Requests must be on).
--=====================================================================

-- which world (place) this came from (ReplicatedStorage.WorldConfig: "World 1", "World 2"...),
-- on the end of every title, the same way the bug reports say it
local WORLD = (function()
	local ok, cfg = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig", 10)) end)
	return ok and cfg and cfg.Name or ("Place " .. game.PlaceId)
end)()

local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")

local WEBHOOK = "https://webhook-relay.jaihoadam12.workers.dev/api/webhooks/1554434892253888614/fanFZrUYaKQcPQL9lsmUdOZrn3tPfteELR0cxMRWXxotALWmzle7U52KGsxcxx0Z5g0Z?key=8Rdasfa9SDHsd89238wefhADFSJF3jas2"
local TRIES             = 3
local COOLDOWN          = 60
local SERVER_PER_MINUTE = 20

local AntiCheatWebhook = {}

local lastSent = {}   -- ["userId|what"] = os.clock()
local recent   = {}   -- os.clock() of each message this last minute

-- red for a ride that was ended, orange for protection only
local function colour(certainty, acted)
	if acted then return 0xE8484F end
	return certainty >= 60 and 0xF0A030 or 0xF0D060
end

local function post(body, what)
	for try = 1, TRIES do
		local ok, err = pcall(HttpService.PostAsync, HttpService, WEBHOOK, body, Enum.HttpContentType.ApplicationJson)
		if ok then return end
		if try == TRIES then
			warn("[AntiCheatWebhook] couldn't report " .. what .. ": " .. tostring(err))
		else
			task.wait(5 * try)
		end
	end
end

function AntiCheatWebhook.Report(player, info)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local now = os.clock()
	local key = player.UserId .. "|" .. tostring(info.What)
	if lastSent[key] and now - lastSent[key] < COOLDOWN then return end
	for i = #recent, 1, -1 do if now - recent[i] > 60 then table.remove(recent, i) end end
	if #recent >= SERVER_PER_MINUTE then return end
	lastSent[key] = now
	table.insert(recent, now)

	local certainty = math.clamp(math.floor(tonumber(info.Certainty) or 0), 0, 100)
	local acted = info.Action ~= nil and info.Action:find("ended") ~= nil
	local server = game.JobId ~= "" and game.JobId or "Studio test"
	if game.PrivateServerId ~= "" then server ..= " (private server)" end
	local fields = {
		{ name = "Player", value = ("%s (@%s)\n[Profile](https://www.roblox.com/users/%d/profile) - UserId %d")
			:format(player.DisplayName, player.Name, player.UserId, player.UserId), inline = false },
		{ name = "What happened", value = tostring(info.What) .. (info.Detail and ("\n" .. info.Detail) or ""), inline = false },
		{ name = "Certainty", value = certainty .. "%", inline = true },
		{ name = "Action", value = info.Action or "None (watched only)", inline = true },
	}
	if info.Partner then table.insert(fields, { name = "Duo partner", value = info.Partner, inline = false }) end
	table.insert(fields, { name = "Server", value = ("%s\nPlace version %d - %d players"):format(server, game.PlaceVersion, #game:GetService("Players"):GetPlayers()), inline = false })

	task.spawn(post, HttpService:JSONEncode({
		username = "Anti-Cheat",
		allowed_mentions = { parse = {} },
		embeds = { {
			title = (RunService:IsStudio() and "[Studio test] " or "") .. "Anti-cheat: " .. tostring(info.What) .. " - " .. WORLD,
			color = colour(certainty, acted),
			fields = fields,
			timestamp = DateTime.now():ToIsoDate(),
		} },
	}), ("%s for %s"):format(tostring(info.What), player.Name))
end

return AntiCheatWebhook
