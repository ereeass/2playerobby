-- Volcano (see ReplicatedStorage.VolcanoCycle): plays the eruption on THIS player's screen off the
-- shared server clock - the fountain, the lava running down, spreading over the road, fading.
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local VolcanoCycle      = require(game:GetService("ReplicatedStorage"):WaitForChild("VolcanoCycle"))

local FOUNTAIN_HEIGHT = 34
local volcanoes = {}

local function add(m)
	if volcanoes[m] or not m:IsA("Model") then return end
	local fountain, pool, flow = m:FindFirstChild("Fountain"), m:FindFirstChild("Pool"), m:FindFirstChild("Flow")
	if not (fountain and pool and flow) then return end
	local segs = {}
	for _, p in ipairs(flow:GetChildren()) do if p:IsA("BasePart") then table.insert(segs, p) end end
	table.sort(segs, function(a, b) return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0) end)
	local arriveX = pool:GetAttribute("ArriveX") or pool.Position.X
	volcanoes[m] = {
		fountain = fountain, base = fountain.CFrame, fw = fountain.Size.Y,
		bombs = fountain:FindFirstChild("Bombs"),
		pool = pool, poolCF = pool.CFrame, poolSize = pool.Size, light = pool:FindFirstChildOfClass("PointLight"),
		arrive = pool.CFrame:PointToObjectSpace(Vector3.new(arriveX, pool.Position.Y, pool.Position.Z)).X,
		segs = segs,
		warning = m:FindFirstChild("Warning"),
	}
end

for _, m in ipairs(CollectionService:GetTagged("Volcano")) do add(m) end
CollectionService:GetInstanceAddedSignal("Volcano"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("Volcano"):Connect(function(m) volcanoes[m] = nil end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for m, v in pairs(volcanoes) do
		if not m.Parent or not v.pool.Parent then volcanoes[m] = nil continue end
		local s = VolcanoCycle.State(m, now)
		if s.erupting and v.wasErupting == false then Sfx.Play("Volcano", m:FindFirstChild("Crater") or v.pool) end   -- it just blew
		v.wasErupting = s.erupting
		-- fountain: rises out of the crater and drops back
		local h = FOUNTAIN_HEIGHT * s.fountain
		if h > 0.5 then
			v.fountain.Transparency = 0.1
			v.fountain.Size = Vector3.new(h, v.fw * (0.6 + 0.4 * s.fountain), v.fw * (0.6 + 0.4 * s.fountain))
			v.fountain.CFrame = v.base * CFrame.new(h / 2, 0, 0)      -- the cylinder's axis (X) points up
		else
			v.fountain.Transparency = 1
		end
		if v.bombs then v.bombs.Enabled = s.erupting end
		-- the river: pieces light up one after another as it runs down
		local n = #v.segs
		for i, seg in ipairs(v.segs) do
			seg.Transparency = (s.flow >= (i - 1) / n and s.flow > 0) and (0.05 + 0.95 * s.fade) or 1
		end
		-- the red warning on the road: grows out from where the river will land to the whole area
		-- the lava is about to cover, pulsing faster and brighter; the lava then spreads over it
		local z = v.warning
		if z then
			if s.warn > 0 then
				local full = v.poolSize
				local g = 1 - (1 - s.warn) ^ 2
				local w = math.max(0.5, full.X * g)
				local d = math.max(0.5, full.Z * g)
				local cx = math.clamp(v.arrive, -full.X / 2 + w / 2, full.X / 2 - w / 2)
				z.Size = Vector3.new(w, z.Size.Y, d)
				z.CFrame = v.poolCF * CFrame.new(cx, -full.Y / 2 + 0.06, full.Z / 2 - d / 2)
				z.Transparency = 0.7 - 0.4 * s.warn - 0.2 * (0.5 + 0.5 * math.sin(now * (3 + s.warn * 12)))
			elseif s.spread > 0 and s.spread < 1 then
				z.Transparency = 0.1
			else
				z.Transparency = 1
			end
		end
		-- the road: spreads out from where the river lands, then fades
		if s.spread > 0 then
			local full = v.poolSize
			local w = math.max(0.5, full.X * s.spread)
			local d = math.max(0.5, full.Z * s.spread)
			-- grow from the landing point, but never past the pool's ends
			local cx = math.clamp(v.arrive, -full.X / 2 + w / 2, full.X / 2 - w / 2)
			v.pool.Size = Vector3.new(w, full.Y, d)
			v.pool.CFrame = v.poolCF * CFrame.new(cx, 0, full.Z / 2 - d / 2)   -- from the road's volcano side
			v.pool.Transparency = 0.05 + 0.95 * s.fade
			if v.light then v.light.Brightness = 2 * (1 - s.fade) end
		else
			v.pool.Transparency = 1
			if v.light then v.light.Brightness = 0 end
		end
	end
end)
