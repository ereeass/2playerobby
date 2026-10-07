--=====================================================================
-- AntiAfk
--
-- Roblox disconnects a player after 20 minutes without any input. The
-- usual "fake a click with VirtualUser" trick is blocked for game
-- scripts (it needs a capability only Roblox's own scripts have), so this
-- uses the supported route instead: shortly before the 20-minute mark an
-- idle player is re-joined into this SAME server. That resets Roblox's
-- idle timer, and they come back to the lobby with the same people.
--
-- Leaving and re-joining goes through the paths the scooter system
-- already has for anyone who leaves (their ride ends, their capsule slot
-- frees), which the idle kick would have triggered anyway.
--=====================================================================

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService      = game:GetService("RunService")

local player = Players.LocalPlayer

-- Idled reports roughly every 2 minutes; 16 leaves a safe margin before 20.
local REJOIN_AFTER = 18 * 60

local rejoining = false
local triedAnyServer = false

local function rejoin()
	rejoining, triedAnyServer = true, false
	if RunService:IsStudio() then
		print("[AntiAfk] Idle for 16 minutes: a live server re-joins the player here (Studio cannot teleport)")
		return
	end
	local ok, err = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, game.JobId, player)
	if not ok then
		warn("[AntiAfk] Re-join failed: " .. tostring(err))
		rejoining = false
	end
end

-- This server is full or shutting down: any server of the game still beats a disconnect.
TeleportService.TeleportInitFailed:Connect(function(plr, _, message)
	if plr ~= player or not rejoining then return end
	if not triedAnyServer then
		triedAnyServer = true
		if pcall(TeleportService.Teleport, TeleportService, game.PlaceId, player) then return end
	end
	warn("[AntiAfk] Re-join failed: " .. tostring(message))
	rejoining = false                       -- the next Idled report tries again
end)

player.Idled:Connect(function(idleSeconds)
	if idleSeconds >= REJOIN_AFTER and not rejoining then
		rejoin()
	end
end)
