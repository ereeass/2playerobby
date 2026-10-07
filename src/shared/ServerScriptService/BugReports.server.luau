--=====================================================================
-- BugReports   (server)
--
-- The settings window's "Report a Bug" box (StarterGui.SettingsWindow, SettingsUI) sends its
-- text here (ReplicatedStorage.BugReport, a RemoteFunction) and this posts it to the team's
-- Discord channel. The webhook lives only here on the server, so players never see it.
--   * 5..MAX_LEN characters, one report per player every COOLDOWN seconds, and at most
--     SERVER_PER_MINUTE a minute from the whole server (Discord's own rate limit)
--   * pings (@everyone, @here, users, roles) are switched off in the message
-- Needs Game Settings > Security > Allow HTTP Requests.
-- Returns true, or false and the reason to show the player.
--=====================================================================

local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local WEBHOOK = "https://webhook-relay.jaihoadam12.workers.dev/api/webhooks/1553986365090439280/XF3N4X2DycjFPjlhblRy1cDuvw2hMGVqTe9hQyVwkBBzdVgP01CUiwTHHzMJl87jcEkZ?key=8Rdasfa9SDHsd89238wefhADFSJF3jas2"

local MIN_LEN, MAX_LEN   = 5, 500
local COOLDOWN           = 60     -- seconds between one player's reports
local SERVER_PER_MINUTE  = 20

local remote = ReplicatedStorage:WaitForChild("BugReport")
-- which world (place) the report came from (ReplicatedStorage.WorldConfig: "World 1", "World 2"...)
local WORLD  = (function()
	local ok, cfg = pcall(function() return require(ReplicatedStorage:WaitForChild("WorldConfig", 10)) end)
	return ok and cfg and cfg.Name or ("Place " .. game.PlaceId)
end)()

local lastSent = {}   -- [player] = os.clock() of their last report
local recent   = {}   -- os.clock() of every report this last minute

local function clean(text)
	text = text:gsub("[%c]", " ")          -- no control characters / new lines
	text = text:gsub("%s+", " ")
	return (text:match("^%s*(.-)%s*$"))
end

remote.OnServerInvoke = function(player, text)
	if type(text) ~= "string" then return false, "Something went wrong." end
	text = clean(text)
	if utf8.len(text) == nil then return false, "Something went wrong." end
	if #text < MIN_LEN then return false, "Tell us a bit more first." end
	if utf8.len(text) > MAX_LEN then return false, ("Keep it under %d characters."):format(MAX_LEN) end

	local now = os.clock()
	if lastSent[player] and now - lastSent[player] < COOLDOWN then
		return false, ("You can send another in %ds."):format(math.ceil(COOLDOWN - (now - lastSent[player])))
	end
	for i = #recent, 1, -1 do
		if now - recent[i] > 60 then table.remove(recent, i) end
	end
	if #recent >= SERVER_PER_MINUTE then return false, "Lots of reports right now, try again soon." end
	lastSent[player] = now
	table.insert(recent, now)

	local body = HttpService:JSONEncode({
		username = "Bug Reports",
		allowed_mentions = { parse = {} },
		embeds = { {
			title = "Bug report - " .. WORLD,
			description = text,
			color = 0x4CC458,
			fields = {
				{ name = "World", value = WORLD, inline = true },
				{ name = "Player", value = ("%s (@%s)\nUserId %d"):format(player.DisplayName, player.Name, player.UserId), inline = true },
				{ name = "Server", value = ("%s\n%d players"):format(RunService:IsStudio() and "Studio" or game.JobId, #Players:GetPlayers()), inline = true },
			},
			timestamp = DateTime.now():ToIsoDate(),
		} },
	})
	local ok, err = pcall(function()
		HttpService:PostAsync(WEBHOOK, body, Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then
		lastSent[player] = nil   -- theirs didn't go: let them try again
		warn("[BugReports] couldn't send: " .. tostring(err))
		return false, "Couldn't send right now, try again later."
	end
	return true
end

Players.PlayerRemoving:Connect(function(player) lastSent[player] = nil end)
