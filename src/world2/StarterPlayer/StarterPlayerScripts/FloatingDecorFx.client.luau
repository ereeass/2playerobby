-- Background decorations that float (Models tagged "FloatingDecor", e.g. Workspace > Floating
-- Heart): a slow, gentle bob up and down with a slight sway, on THIS player's screen.
-- Attributes on the Model: BobHeight (studs, default 1.5), BobTime (seconds a bob, default 4),
-- SwayDeg (degrees of sway, default 3). Its PrimaryPart is the middle it floats around.
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local items = {}

local function add(m)
	if items[m] or not m:IsA("Model") or not m.PrimaryPart then return end
	local origin = m:GetPivot()
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, { p, origin:ToObjectSpace(p.CFrame) }) end
	end
	items[m] = { origin = origin, parts = parts, phase = (origin.Position.X + origin.Position.Z) % 10 }
end

for _, m in ipairs(CollectionService:GetTagged("FloatingDecor")) do add(m) end
CollectionService:GetInstanceAddedSignal("FloatingDecor"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("FloatingDecor"):Connect(function(m) items[m] = nil end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for m, it in pairs(items) do
		if not m.Parent then items[m] = nil continue end
		local period = m:GetAttribute("BobTime") or 4
		local a = (now + it.phase) / period * math.pi * 2
		local y = math.sin(a) * (m:GetAttribute("BobHeight") or 1.5)
		local sway = math.rad(m:GetAttribute("SwayDeg") or 3) * math.sin(a * 0.5)
		local cf = it.origin * CFrame.new(0, y, 0) * CFrame.Angles(0, sway, 0)
		for _, pr in ipairs(it.parts) do pr[1].CFrame = cf * pr[2] end
	end
end)
