-- Stomp bears (see ReplicatedStorage.BearStomp): moves every bear on THIS player's screen off
-- the shared server clock, so it's smooth and in step for everyone. A little squash when it lands.
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local BearStomp         = require(game:GetService("ReplicatedStorage"):WaitForChild("BearStomp"))

local bears = {}
local WARN = 1.1   -- seconds before the stomp that the red square under the bear starts pulsing

local function add(m)
	if bears[m] or not m:IsA("Model") then return end
	local base = m:FindFirstChild("Footprint")
	if not base then return end
	local origin = base.CFrame
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= base and p.Name ~= "Warning" then table.insert(parts, { p, origin:ToObjectSpace(p.CFrame) }) end
	end
	bears[m] = { origin = origin, parts = parts, base = base, warning = m:FindFirstChild("Warning") }
end

for _, m in ipairs(CollectionService:GetTagged("StompBear")) do add(m) end
CollectionService:GetInstanceAddedSignal("StompBear"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("StompBear"):Connect(function(m) bears[m] = nil end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for m, b in pairs(bears) do
		if not m.Parent or not b.base.Parent then bears[m] = nil continue end
		local h, phase, pk = BearStomp.State(m, now)
		if phase == "ground" and b.lastPhase and b.lastPhase ~= "ground" then Sfx.Play("StompBear", m:FindFirstChild("Body")) end   -- it just landed
		b.lastPhase = phase
		-- the red square on the road (like the hammers / tentacles): pulses faster and brighter
		-- right before the stomp, flashes on impact, fades while the bear sits there
		local z = b.warning
		if z then
			local left = phase == "air" and (m:GetAttribute("AirTime") or 2) * (1 - pk) or math.huge
			if left < WARN then
				local w = 1 - left / WARN
				z.Transparency = 0.75 - 0.45 * w - 0.2 * (0.5 + 0.5 * math.sin(now * (3 + w * 12)))
			elseif phase == "drop" then
				z.Transparency = 0.1
			elseif phase == "ground" then
				z.Transparency = 0.1 + 0.9 * math.min(1, pk * 1.5)
			else
				z.Transparency = 1
			end
		end
		-- squash for a moment after landing (first 0.25 s on the ground)
		local squash = 1
		if phase == "ground" then
			local since = (now - (m:GetAttribute("Offset") or 0)) % 1e6
			local g = m:GetAttribute("GroundTime") or 1.2
			local cyc = g + (m:GetAttribute("RiseTime") or 0.9) + (m:GetAttribute("AirTime") or 2) + (m:GetAttribute("DropTime") or 0.35)
			local t = since % cyc
			if t < 0.25 then squash = 1 - 0.12 * math.sin(t / 0.25 * math.pi) end
		end
		local cf = b.origin + Vector3.new(0, h, 0)
		for _, pr in ipairs(b.parts) do
			local rel = pr[2]
			if squash ~= 1 then rel = CFrame.new(rel.Position.X, (rel.Position.Y + 0.5) * squash - 0.5, rel.Position.Z) * rel.Rotation end
			pr[1].CFrame = cf * rel
		end
	end
end)
