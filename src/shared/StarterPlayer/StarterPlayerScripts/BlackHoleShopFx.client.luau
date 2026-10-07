-- The black hole on display in the Black Hole Podium's glass case (tagged "BlackHoleDisplay"):
-- it bobs gently like the nuke and the dragon beside it, its disc turns, its halo shimmers
-- round, its glow and jets pulse, and a few little chunks spiral in off the disc and vanish into
-- it. This machine's picture only (the chunks are this machine's own, never sent anywhere).

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local TAG    = "BlackHoleDisplay"
local BOB    = 0.12   -- studs up and down
local SPIN   = 1.3    -- the disc's turn, radians a second
local CHUNKS = 7      -- little chunks spiralling in
local FALL   = 0.28   -- each chunk's trips in a second (from the disc's edge into the core)
local EDGE   = 1.9    -- where they start: the disc's edge, studs from the middle
local CHUNK_COLORS = {
	Color3.fromRGB(95, 160, 70), Color3.fromRGB(120, 95, 70), Color3.fromRGB(130, 130, 135),
	Color3.fromRGB(190, 150, 255), Color3.fromRGB(160, 140, 110),
}

-- [model] = { rest = the core's resting CFrame, parts = { [part] = offset from it }, ... }
local shown = {}

local function add(model)
	if not model:IsA("Model") or shown[model] then return end
	local core = model:FindFirstChild("Core")
	if not core then return end
	local rest = CFrame.new(core.Position)
	local e = { rest = rest, parts = {}, chunks = {} }
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then e.parts[p] = rest:ToObjectSpace(p.CFrame) end
	end
	e.disc = model:FindFirstChild("Disc")
	e.halo = model:FindFirstChild("Halo")
	e.light = core:FindFirstChild("Glow")
	e.jets = {}
	for _, n in ipairs({ "JetUp", "JetDown" }) do
		local j = model:FindFirstChild(n)
		if j then table.insert(e.jets, { part = j, was = j.Transparency }) end
	end
	-- the chunks: this machine's own, in a folder of their own
	local folder = Instance.new("Folder")
	folder.Name = "LocalChunks"
	folder.Parent = model
	e.folder = folder
	for i = 1, CHUNKS do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.CastShadow = false
		p.Material = (i % 3 == 0) and Enum.Material.Slate or Enum.Material.SmoothPlastic
		p.Color = CHUNK_COLORS[i % #CHUNK_COLORS + 1]
		p.Size = Vector3.new(0.14, 0.11, 0.12) * (1 + (i % 3) * 0.35)
		p.Parent = folder
		e.chunks[i] = { part = p, size = p.Size, phase = (i - 1) / CHUNKS, a0 = i * 2.39996 }
	end
	shown[model] = e
end

local function remove(model)
	local e = shown[model]
	shown[model] = nil
	if e and e.folder then e.folder:Destroy() end
end

for _, m in ipairs(CollectionService:GetTagged(TAG)) do task.defer(add, m) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, e in pairs(shown) do
		if not model.Parent then
			remove(model)
			continue
		end
		local base = e.rest + Vector3.new(0, math.sin(t * 1.6) * BOB, 0)
		for p, off in pairs(e.parts) do
			if p == e.disc then
				p.CFrame = base * off * CFrame.Angles(0, t * SPIN, 0)
			elseif p == e.halo then
				p.CFrame = base * off * CFrame.Angles(t * 0.5, t * 0.8, 0)
			else
				p.CFrame = base * off
			end
		end
		-- its glow breathing, its jets flickering
		if e.light then e.light.Brightness = 1.8 + 0.7 * math.sin(t * 2.3) end
		for i, j in ipairs(e.jets) do
			j.part.Transparency = math.clamp(j.was + 0.15 * math.sin(t * 9 + i * 2), 0, 1)
		end
		-- the chunks: round and round in the disc's plane, faster as they fall in, gone into the core
		local plane = e.disc and (base * e.parts[e.disc]) or base
		for i, c in ipairs(e.chunks) do
			local u = (t * FALL + c.phase) % 1
			local r = EDGE * (1 - u) ^ 1.2
			local a = c.a0 + u * u * 7
			local k = (1 - u ^ 4) * math.clamp(u / 0.1, 0, 1)
			c.part.Size = c.size * math.max(k, 0.05)
			c.part.Transparency = (r < 0.55 or k < 0.06) and 1 or 0
			c.part.CFrame = plane * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(t * 3 + i, t * 2, 0)
		end
	end
end)
