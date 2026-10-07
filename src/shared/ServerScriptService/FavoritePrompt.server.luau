--=====================================================================
-- FavoritePrompt   (server)
--
-- Roblox's "Favorite this experience?" prompt, ONCE per player, ever (both worlds share the
-- save, so seeing it in one world means never again in either):
--   * only for a player who has checkpoint 2 or higher (in this world)
--   * only when they come back to the lobby by respawning - never on joining, never on a
--     revive (that keeps them in their run) and never while they're in a ride or a booth
--   * a few seconds after they land, so it doesn't sit on top of anything else
-- The save flag is written as soon as it is shown (closing it counts as seen).
-- The prompt itself is shown by StarterPlayerScripts.FavoritePromptClient.
--=====================================================================

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RS                  = game:GetService("ReplicatedStorage")

local ScooterSystem      = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager        = require(ScooterSystem:WaitForChild("RideManager"))
local TeamManager        = require(ScooterSystem:WaitForChild("TeamManager"))
local CheckpointProgress = require(ScooterSystem:WaitForChild("CheckpointProgress"))

local KEY        = "FavoritePromptShown"   -- in the player's save (SettingsServer's PlayerData)
local MIN_ORDER  = 2                       -- checkpoint 2 unlocked
local SHOW_AFTER = 4                       -- seconds after landing in the lobby

local remotes = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local remote = remotes:FindFirstChild("FavoritePrompt")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "FavoritePrompt"
	remote.Parent = remotes
end

local dataApi
local function data()
	if dataApi and dataApi.Parent then return dataApi end
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 10)
	return dataApi
end

local done = {}   -- [player] = true: shown (now or ever) - or their save couldn't be read

local function loadFlag(player)
	local api = data()
	local ok, value, state
	if api then ok, value, state = pcall(api.Get.Invoke, api.Get, player, KEY) end
	-- unreadable save: don't risk showing it a second time
	if not ok or state == "failed" or state == "invalid" or value == true then done[player] = true end
end

local function eligible(player)
	if done[player] or not player.Parent then return false end
	if (CheckpointProgress.Get(player)) < MIN_ORDER then return false end
	if RideManager.IsReviving(player) or RideManager.PlayerRide[player] then return false end
	if TeamManager.FindSlot(player) then return false end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function onRespawn(player, character)
	if not eligible(player) then return end
	task.wait(SHOW_AFTER)
	if player.Character ~= character or not eligible(player) then return end
	done[player] = true
	remote:FireClient(player)
	local api = data()
	if api then task.spawn(pcall, api.SaveNow.Invoke, api.SaveNow, player, KEY, true) end
	print("[Favorite] prompted " .. player.Name)
end

local function hook(player)
	task.spawn(loadFlag, player)
	local first = player.Character == nil   -- the join spawn doesn't count: only respawns do
	player.CharacterAdded:Connect(function(character)
		if first then first = false return end
		task.spawn(onRespawn, player, character)
	end)
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerRemoving:Connect(function(player) done[player] = nil end)
