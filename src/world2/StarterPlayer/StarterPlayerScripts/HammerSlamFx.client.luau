-- Heart hammers (see ReplicatedStorage.HammerSlam): swings every hammer on THIS player's screen
-- off the shared server clock, so it's smooth and in step for everyone.
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local HammerSlam        = require(game:GetService("ReplicatedStorage"):WaitForChild("HammerSlam"))

local hammers = {}
local WARN = 1.1   -- seconds before the slam that the red square under the head starts pulsing

local function add(m)
	if hammers[m] or not m:IsA("Model") then return end
	local stand, hammer = m:FindFirstChild("Stand"), m:FindFirstChild("Hammer")
	local pivot = stand and stand:FindFirstChild("Pivot")
	if not (pivot and hammer) then return end
	-- the pivot frame: X toward the road, Z along it (the axle part lies along Z)
	local pv = pivot.CFrame * CFrame.Angles(0, -math.pi / 2, 0)
	local rest = math.rad(m:GetAttribute("RestDeg") or 100)
	local parts = {}
	for _, p in ipairs(hammer:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, { p, CFrame.Angles(0, 0, -rest) * pv:ToObjectSpace(p.CFrame) }) end
	end
	hammers[m] = { pv = pv, parts = parts, pivot = pivot, warning = m:FindFirstChild("Warning"), head = hammer:FindFirstChild("Head") }
end

for _, m in ipairs(CollectionService:GetTagged("HeartHammer")) do add(m) end
CollectionService:GetInstanceAddedSignal("HeartHammer"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("HeartHammer"):Connect(function(m) hammers[m] = nil end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for m, h in pairs(hammers) do
		if not m.Parent or not h.pivot.Parent then hammers[m] = nil continue end
		local a, phase, k = HammerSlam.State(m, now)
		if phase == "down" and h.lastPhase and h.lastPhase ~= "down" then Sfx.Play("HeartHammer", h.head) end   -- it just landed
		h.lastPhase = phase
		local cf = h.pv * CFrame.Angles(0, 0, a)
		for _, pr in ipairs(h.parts) do pr[1].CFrame = cf * pr[2] end
		-- the red square on the road (like the octopus tentacles): pulses faster and brighter
		-- right before the slam, flashes on impact, fades while the head rests on the road
		local z = h.warning
		if z then
			local left = phase == "up" and (m:GetAttribute("UpTime") or 1.3) * (1 - k) or math.huge
			if left < WARN then
				local w = 1 - left / WARN
				z.Transparency = 0.75 - 0.45 * w - 0.2 * (0.5 + 0.5 * math.sin(now * (3 + w * 12)))
			elseif phase == "slam" then
				z.Transparency = 0.1
			elseif phase == "down" then
				z.Transparency = 0.1 + 0.9 * k
			else
				z.Transparency = 1
			end
		end
	end
end)
