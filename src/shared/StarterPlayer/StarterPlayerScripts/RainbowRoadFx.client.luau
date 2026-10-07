-- Rainbow Road (Workspace > Rainbow Road): the colours drift slowly along the road so it
-- shimmers like a hologram. Looks only, on this player's screen; nothing about driving on it
-- changes. Each band remembers its place (Band across, Along the road) as attributes.

local CollectionService = game:GetService("CollectionService")

local BANDS  = 6
local SPEED  = 0.04      -- how fast the rainbow drifts (turns of the colour wheel per second)
local STEP   = 0.1       -- seconds between colour updates

local roads = {}
local function add(m)
	if roads[m] then return end
	local list = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Band") then
			local b = p:GetAttribute("Band")
			local edge = b == 0 or b > BANDS
			table.insert(list, { p, math.clamp(b, 1, BANDS), p:GetAttribute("Along") or 0, edge })
		end
	end
	roads[m] = list
end
for _, m in ipairs(CollectionService:GetTagged("RainbowRoad")) do add(m) end
CollectionService:GetInstanceAddedSignal("RainbowRoad"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("RainbowRoad"):Connect(function(m) roads[m] = nil end)

while true do
	local shift = (os.clock() * SPEED) % 1
	for m, list in pairs(roads) do
		if not m.Parent then roads[m] = nil continue end
		for _, e in ipairs(list) do
			local h = ((e[2] - 1) / BANDS * 0.85 + e[3] / 180 + shift) % 1
			e[1].Color = Color3.fromHSV(h, e[4] and 0.25 or 0.42, 1)
		end
	end
	task.wait(STEP)
end
