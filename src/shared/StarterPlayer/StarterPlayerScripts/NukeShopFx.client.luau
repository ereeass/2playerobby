-- The nuke on display in the Nuke Podium's glass case (tagged "NukeDisplay") bobs and turns
-- slowly, like the scooters on their podiums. This machine's picture only.

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local TAG   = "NukeDisplay"
local SPIN  = 0.6    -- radians a second
local BOB   = 0.25   -- studs up and down

-- [model] = { rest = its resting pivot, parts = { [part] = offset from it } }. Each part is
-- placed from its own offset, so a part that streams in late (it arrives where the server
-- has it, at rest) joins in instead of being left behind.
local shown = {}

local function add(model)
	if not model:IsA("Model") or shown[model] then return end
	-- it turns round its own middle (its bounding box), wherever its pivot was left after resizing
	local box = model:GetBoundingBox()
	local rest = CFrame.new(box.Position) * model:GetPivot().Rotation
	local entry = { rest = rest, parts = {} }
	local function track(p)
		if p:IsA("BasePart") then entry.parts[p] = rest:ToObjectSpace(p.CFrame) end
	end
	for _, d in ipairs(model:GetDescendants()) do track(d) end
	model.DescendantAdded:Connect(track)
	model.DescendantRemoving:Connect(function(p) entry.parts[p] = nil end)
	shown[model] = entry
end
for _, m in ipairs(CollectionService:GetTagged(TAG)) do add(m) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m) shown[m] = nil end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, e in pairs(shown) do
		if model.Parent then
			local rest = e.rest
			local cf = CFrame.new(0, math.sin(t * 1.6) * BOB, 0) * CFrame.new(rest.Position) * CFrame.Angles(0, t * SPIN, 0) * rest.Rotation
			for p, off in pairs(e.parts) do p.CFrame = cf * off end
		else
			shown[model] = nil
		end
	end
end)
