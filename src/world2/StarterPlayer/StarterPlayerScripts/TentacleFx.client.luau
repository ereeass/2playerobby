-- Octopus tentacles (see ReplicatedStorage.TentacleCycle): swings every tentacle and lights its
-- warning strip on THIS player's screen, off the shared server clock.
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local TentacleCycle     = require(game:GetService("ReplicatedStorage"):WaitForChild("TentacleCycle"))

local items = {}

local function add(m)
	if items[m] or not m:IsA("Model") then return end
	local pivot, arm, zone = m:FindFirstChild("Pivot"), m:FindFirstChild("Arm"), m:FindFirstChild("Zone")
	if not (pivot and arm and zone) then return end
	local raised = math.rad(m:GetAttribute("RaisedDeg") or 100)
	local parts = {}
	for _, p in ipairs(arm:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, { p, CFrame.Angles(0, 0, -raised) * pivot.CFrame:ToObjectSpace(p.CFrame) }) end
	end
	items[m] = { pivot = pivot.CFrame, parts = parts, zone = zone }
end

for _, m in ipairs(CollectionService:GetTagged("Tentacle")) do add(m) end
CollectionService:GetInstanceAddedSignal("Tentacle"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("Tentacle"):Connect(function(m) items[m] = nil end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for m, it in pairs(items) do
		if not m.Parent or not it.zone.Parent then items[m] = nil continue end
		local a, phase, k = TentacleCycle.State(m, now)
		if phase == "down" and it.lastPhase and it.lastPhase ~= "down" then Sfx.Play("Tentacle", it.zone) end   -- it just hit the road
		it.lastPhase = phase
		local cf = it.pivot * CFrame.Angles(0, 0, a)
		for _, pr in ipairs(it.parts) do pr[1].CFrame = cf * pr[2] end
		-- the red strip: pulses faster and brighter as the smack comes, flashes on impact, fades
		local z = it.zone
		if phase == "warn" then
			local rate = 3 + k * 12
			z.Transparency = 0.75 - 0.45 * k - 0.2 * (0.5 + 0.5 * math.sin(now * rate))
		elseif phase == "slam" then
			z.Transparency = 0.1
		elseif phase == "down" then
			z.Transparency = 0.1 + 0.9 * k
		else
			z.Transparency = 1
		end
	end
end)
