-- Stone Sweeper arms, turned on THIS player's screen. The server
-- (Workspace > Stone Sweeper > StoneSweeperServer) does the pushing from the same shared clock;
-- this sweeps the three rollers round the hub and rolls each one along the floor as it goes,
-- so they move smoothly instead of stepping. Sweepers are found by their "StoneSweeper" tag,
-- whenever they stream in.

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local ARM_Y  = 1.35         -- roller centre above the floor at scale 1 (follows the model's scale)
local ROLLS  = 9            -- roller spins per sweep (~ middle radius 12.3 / roller radius 1.35);
                             -- a whole number, so it doesn't jump when the sweep wraps round

local sweepers = {}          -- [model] = { centre, arms = { { angle, parts = { {part, rel} } } } }

local function add(m)
	if sweepers[m] or not m:IsA("Model") then return end
	local centre, armsM = m:FindFirstChild("Centre"), m:FindFirstChild("Arms")
	if not (centre and armsM) then return end
	local arms = {}
	for _, a in ipairs(armsM:GetChildren()) do
		local th = a:GetAttribute("Angle") or 0
		local frame = centre.CFrame * CFrame.Angles(0, th, 0) * CFrame.new(0, ARM_Y * m:GetScale(), 0)
		local parts = {}
		for _, p in ipairs(a:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(parts, { p, frame:ToObjectSpace(p.CFrame) }) end
		end
		table.insert(arms, { angle = th, parts = parts })
	end
	sweepers[m] = { centre = centre, arms = arms }
end

for _, m in ipairs(CollectionService:GetTagged("StoneSweeper")) do add(m) end
CollectionService:GetInstanceAddedSignal("StoneSweeper"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("StoneSweeper"):Connect(function(m) sweepers[m] = nil end)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	for m, s in pairs(sweepers) do
		if not m.Parent or not s.centre.Parent then sweepers[m] = nil continue end
		local turn  = m:GetAttribute("TurnTime") or 8
		local phase = m:GetAttribute("Phase") or 0
		local a = (((now + phase) % turn) / turn) * math.pi * 2   -- wrapped: CFrame angles need small numbers
		local roll = CFrame.Angles(-a * ROLLS, 0, 0)
		for _, arm in ipairs(s.arms) do
			local frame = s.centre.CFrame * CFrame.Angles(0, a + arm.angle, 0) * CFrame.new(0, ARM_Y * m:GetScale(), 0)
			for _, pr in ipairs(arm.parts) do
				local rel = pr[2]
				-- roll about the arm's own length: keep the part's spot along the arm, spin the rest
				local along = CFrame.new(rel.X, 0, 0)
				pr[1].CFrame = frame * along * roll * along:Inverse() * rel
			end
		end
	end
end)
