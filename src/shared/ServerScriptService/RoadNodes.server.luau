-- The balls that shape a road (tag "RoadNode", or anything in a road's Nodes folder)
-- are Studio-only handles. The built road stays; the handles go before anyone joins,
-- in a real server and in a Studio play test alike.
local CollectionService = game:GetService("CollectionService")

for _, node in ipairs(CollectionService:GetTagged("RoadNode")) do
	node:Destroy()
end

local roads = workspace:FindFirstChild("Roads")
if roads then
	for _, d in ipairs(roads:GetDescendants()) do
		if d:IsA("Folder") and d.Name == "Nodes" then
			d:Destroy()
		end
	end
end
