--=====================================================================
-- ControlsPopupServer
--
-- The ride's controls popup (RideGui.Controller: "Hold W - Accelerate" ...) is shown once
-- per player, ever: the first ride they start from checkpoint 1. Remembered as
-- HasSeenControlsPopup in the player's save (SettingsServer's PlayerData, server-only, shared
-- by every world). The client asks ScooterSystem.Remotes.ControlsPopup when it boards a ride
-- from checkpoint 1; the answer is true only the first time, and asking marks it seen.
-- If the save can't be read, it says true and marks nothing (seeing it twice is harmless).
--=====================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KEY     = "HasSeenControlsPopup"
local remotes = ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Remotes")

local remote = remotes:FindFirstChild("ControlsPopup")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "ControlsPopup"
	remote.Parent = remotes
end

local dataApi
local function api()
	if dataApi then return dataApi end
	local settings = script.Parent:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 30)
	return dataApi
end

local asked = {}   -- [player] = true once answered this visit (one answer per visit is plenty)

remote.OnServerInvoke = function(player)
	if asked[player] then return false end
	asked[player] = true
	local d = api()
	if not d then return true end
	local ok, value, state = pcall(d.Get.Invoke, d.Get, player, KEY)
	if not ok or state == "failed" or state == "invalid" then return true end
	if value == true then return false end
	pcall(d.Set.Invoke, d.Set, player, KEY, true)
	return true
end

Players.PlayerRemoving:Connect(function(player) asked[player] = nil end)
