-- Candy Rooms (Workspace > Candy Rooms): each round room turns like a turntable, the way
-- its floor arrows point. Every player's machine turns them itself, off the shared server
-- clock, so they're smooth and in step on every screen. Whoever is on one is carried round
-- with it: the floor is given the turning speed as well (Roblox moves whatever rests on a
-- part with velocity), and the machine simulating a scooter - its driver's - is the one
-- that matters for riding.
-- Tuning: attributes on each room model (tag "CandySpinner")
--   SpinDirection  1 = clockwise seen from above, -1 = anticlockwise
--   SpinSpeed      radians per second

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local UP_INV = CFrame.Angles(0, 0, math.pi / 2):Inverse()   -- the floor is an upright cylinder
local rooms = {}

local function add(m)
	if rooms[m] or not m:IsA("Model") then return end
	local floor = m:FindFirstChild("Floor")
	if not floor then return end
	local centre = floor.CFrame * UP_INV              -- flat frame at the floor's middle
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, { p, centre:ToObjectSpace(p.CFrame) }) end
	end
	rooms[m] = { centre = centre, parts = parts, floor = floor }
end

for _, m in ipairs(CollectionService:GetTagged("CandySpinner")) do add(m) end
CollectionService:GetInstanceAddedSignal("CandySpinner"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("CandySpinner"):Connect(function(m) rooms[m] = nil end)

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for m, r in pairs(rooms) do
		if not m.Parent or not r.floor.Parent then rooms[m] = nil continue end
		local speed = m:GetAttribute("SpinSpeed") or 0.3
		local cw    = (m:GetAttribute("SpinDirection") or 1) >= 0 and 1 or -1
		if speed > 0 then
			local period = math.pi * 2 / speed
			-- wrapped to one turn first: a CFrame angle only keeps precision for small numbers.
			-- Clockwise from above is a negative turn about +Y.
			local a = -cw * ((now % period) / period) * math.pi * 2
			local cf = r.centre * CFrame.Angles(0, a, 0)
			for _, pr in ipairs(r.parts) do pr[1].CFrame = cf * pr[2] end
			r.floor.AssemblyAngularVelocity = Vector3.new(0, -cw * speed, 0)
		end
	end
end)
