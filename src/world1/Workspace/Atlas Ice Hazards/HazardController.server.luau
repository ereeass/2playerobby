-- Moving ice hazards round the Atlas spiral (Workspace["Atlas Ice Hazards"].Moving):
--   SpikeTrap  the plate glows, then a set of ice spikes shoots up on one half of the road
--   Snowball   a snowball rolls across the road, pausing at each edge
--   Slider     an ice block slides in from the edge to the centre line and back
--   Spinner    an ice blade spins round a post on the edge, sweeping half the road
-- Every hazard model here and in Static is tagged "KillZone" (ServerScriptService.KillZones:
-- a scooter touching it ends the run like the water). Parts moved by script don't always
-- report touches, so this also checks each moving hazard's space every frame.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager  = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager = require(ScooterSystem:WaitForChild("DeathManager"))

local movers = script.Parent:WaitForChild("Moving")
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local items = {}
for _, m in ipairs(movers:GetChildren()) do
	local e = { model = m, kind = m:GetAttribute("Kind"), offset = m:GetAttribute("Offset") or 0, parts = {} }
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(e.parts, { part = p, cf = p.CFrame }) end
	end
	if e.kind == "SpikeTrap" then
		e.up = m:GetAttribute("Up")
		e.plate = m:FindFirstChild("WarningPlate")
		e.plateColor = e.plate.Color
		e.spikes = {}
		for _, x in ipairs(e.parts) do if x.part:IsDescendantOf(m.Spikes) then table.insert(e.spikes, x) end end
	elseif e.kind == "Snowball" or e.kind == "Slider" then
		e.from, e.to = m:GetAttribute("From"), m:GetAttribute("To")
		e.main = m:FindFirstChild("Snowball") or m:FindFirstChild("Block")
		e.axis = m:GetAttribute("Axis")
	elseif e.kind == "Spinner" then
		e.hub = m:GetAttribute("Hub")
		e.blade = {}
		for _, x in ipairs(e.parts) do if x.part.Name == "Blade" or x.part.Name == "BladeTip" then table.insert(e.blade, x) end end
	end
	table.insert(items, e)
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { scooters }
-- (DeathManager.Hit brings a ride down once; more hits while it is down do nothing)
local function strike(part)
	for _, h in ipairs(workspace:GetPartsInPart(part, params)) do
		local m = h:FindFirstAncestorOfClass("Model")
		while m and m.Parent ~= scooters do m = m:FindFirstAncestorOfClass("Model") end
		local ride = m and RideManager.Rides[m]
		if ride and not ride._ended and not ride.Down then
			DeathManager.Hit(ride)
		end
	end
end

local function ease(t) return t * t * (3 - 2 * t) end
local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local now = os.clock() - t0
	for _, e in ipairs(items) do
		local t = now + e.offset
		if e.kind == "SpikeTrap" then
			-- 4 s cycle: 2.2 s down, 0.8 s warning glow, 1 s up
			local c = t % 4
			local up = 0
			if c > 3 then up = 1 elseif c > 2.9 then up = (c - 2.9) / 0.1 end
			if c > 3.8 then up = math.max(0, (4 - c) / 0.2) end
			local warn = c > 2.2 and c <= 3.8
			e.plate.Color = warn and ((math.floor(c * 8) % 2 == 0) and Color3.fromRGB(120, 230, 255) or e.plateColor) or e.plateColor
			e.plate.Material = warn and Enum.Material.Neon or Enum.Material.SmoothPlastic
			for _, x in ipairs(e.spikes) do x.part.CFrame = x.cf + e.up * up end
			if up > 0.3 then for _, x in ipairs(e.spikes) do if x.part.Name == "Spike" then strike(x.part) end end end
		elseif e.kind == "Snowball" then
			-- 4 s cycle: roll across (1.1 s), wait (0.9 s), roll back, wait
			local c = t % 4
			local k
			if c < 1.1 then k = ease(c / 1.1) elseif c < 2 then k = 1 elseif c < 3.1 then k = 1 - ease((c - 2) / 1.1) else k = 0 end
			local pos = e.from:Lerp(e.to, k)
			local delta = pos - e.from
			local spin = CFrame.fromAxisAngle(e.axis, -delta.Magnitude / 1.4 * (((e.to - e.from):Dot(delta) >= 0) and 1 or -1))
			for _, x in ipairs(e.parts) do
				local rel = x.cf.Position - e.from
				x.part.CFrame = CFrame.new(pos) * spin * CFrame.new(rel) * (x.cf - x.cf.Position)
			end
			strike(e.main)
		elseif e.kind == "Slider" then
			local c = t % 3.6
			local k
			if c < 0.7 then k = ease(c / 0.7) elseif c < 1.8 then k = 1 elseif c < 2.5 then k = 1 - ease((c - 1.8) / 0.7) else k = 0 end
			local d = (e.to - e.from) * k
			for _, x in ipairs(e.parts) do x.part.CFrame = x.cf + d end
			strike(e.main)
		elseif e.kind == "Spinner" then
			local a = t * 2.6
			local r = CFrame.new(e.hub) * CFrame.Angles(0, a, 0) * CFrame.new(-e.hub)
			for _, x in ipairs(e.blade) do x.part.CFrame = r * x.cf end
			strike(e.blade[1].part)
		end
	end
end)
