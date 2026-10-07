--=====================================================================
-- BoothTutorial   (server)
--
-- The first-join booth tutorial (StarterPlayerScripts.BoothTutorial shows it) is shown ONCE
-- per player, ever: both worlds share the save, so finishing or skipping it in one world
-- means never again in either. Only the "seen" flag lives here.
--   BoothTutorialState (RemoteFunction)  -> true if this player should see it
--   BoothTutorialSeen  (RemoteEvent)     <- they finished or skipped it: saved
-- A save that couldn't be read shows it (seeing it twice is harmless; missing it isn't).
--=====================================================================

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RS                  = game:GetService("ReplicatedStorage")

local KEY = "BoothTutorialSeen"   -- in the player's save (SettingsServer's PlayerData)

local remotes = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local function remote(class, name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local stateRemote = remote("RemoteFunction", "BoothTutorialState")
local seenRemote  = remote("RemoteEvent", "BoothTutorialSeen")

local dataApi
local function data()
	if dataApi and dataApi.Parent then return dataApi end
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 10)
	return dataApi
end

local saved = {}   -- [player] = true: marked seen this session

stateRemote.OnServerInvoke = function(player)
	if saved[player] then return false end
	local api = data()
	local ok, value
	if api then ok, value = pcall(api.Get.Invoke, api.Get, player, KEY) end
	return not (ok and value == true)
end

seenRemote.OnServerEvent:Connect(function(player)
	if saved[player] then return end
	saved[player] = true
	local api = data()
	if api then task.spawn(pcall, api.SaveNow.Invoke, api.SaveNow, player, KEY, true) end
end)

Players.PlayerRemoving:Connect(function(player) saved[player] = nil end)
