-- Wires each capsule's ProximityPrompt to TeamManager and keeps the connections
-- so nothing leaks if the system is ever reinitialised.

local TeamManager = require(script.Parent:WaitForChild("TeamManager"))

local CapsuleManager = {}
local connections = {}

function CapsuleManager.Init()
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)

	local folder = workspace:WaitForChild("RideSystem"):WaitForChild("CapsuleStations")
	local n = 0
	for _, st in ipairs(folder:GetChildren()) do
		for _, part in ipairs(st:GetChildren()) do
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				table.insert(connections, prompt.Triggered:Connect(function(player)
					TeamManager.Enter(player, part)
				end))
				n += 1
			end
		end
	end
	print("[Scooter] wired", n, "capsule prompts")
end

return CapsuleManager
