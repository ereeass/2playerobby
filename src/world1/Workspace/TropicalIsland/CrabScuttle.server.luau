-- Each crab in this island scuttles sideways a couple of studs, pauses, and comes back.
-- It always stands ON the ground: when the game starts each crab is set down with its
-- feet on the surface under it, and it only walks where the whole way is solid ground
-- at that same height (never into a step, off an edge, or into a plant or trunk);
-- if neither side is clear it just waits.
local TweenService = game:GetService("TweenService")

local island = script.Parent
local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Include
ground.FilterDescendantsInstances = { island:WaitForChild("Ground"), island:WaitForChild("RockBase") }
local blockers = OverlapParams.new()
blockers.FilterType = Enum.RaycastFilterType.Include
blockers.FilterDescendantsInstances = { island:WaitForChild("PalmTrees"), island:WaitForChild("Plants"), island:WaitForChild("Rocks") }

local HALF_W, HALF_D = 0.9, 0.6   -- a crab's footprint (legs included), half each way
local LEVEL = 0.05                -- how much the ground may differ along a walk

local function groundY(pos)
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), ground)
	return hit and hit.Position.Y
end

-- can the crab slide from home by dist (sideways) and stay on level ground all the way?
local function clear(home, dist, y)
	local step = dist > 0 and 0.4 or -0.4
	for d = 0, dist, step do
		for _, ox in ipairs({ -HALF_W, 0, HALF_W }) do
			for _, oz in ipairs({ -HALF_D, 0, HALF_D }) do
				local gy = groundY((home * CFrame.new(d + ox, 0, oz)).Position)
				if not gy or math.abs(gy - y) > LEVEL then return false end
			end
		end
	end
	local mid = home * CFrame.new(dist / 2, 0, 0)
	return #workspace:GetPartBoundsInBox(mid, Vector3.new(math.abs(dist) + HALF_W * 2, 1, HALF_D * 2), blockers) == 0
end

for _, crab in ipairs(island:WaitForChild("Crabs"):GetChildren()) do
	local body = crab:FindFirstChild("Body")
	if body then
		task.spawn(function()
			-- feet on the ground under it
			local low = math.huge
			for _, p in ipairs(crab:GetDescendants()) do
				if p:IsA("BasePart") then low = math.min(low, p.Position.Y - p.Size.Y / 2) end
			end
			local feet = body.Position.Y - low
			local y = groundY(body.Position)
			if not y then return end                          -- not over the island: leave it be
			local home = body.CFrame + Vector3.new(0, y + 0.02 + feet - body.Position.Y, 0)
			body.CFrame = home
			task.wait(math.random() * 3)
			while body.Parent do
				local side = math.random() < 0.5 and -1 or 1
				local dist = 1.5 + math.random() * 1.5
				if not clear(home, side * dist, y) then
					side = -side
					if not clear(home, side * dist, y) then side = 0 end
				end
				if side ~= 0 then
					local t = 0.6 + math.random() * 0.5
					TweenService:Create(body, TweenInfo.new(t, Enum.EasingStyle.Sine), { CFrame = home * CFrame.new(side * dist, 0, 0) }):Play()
					task.wait(t + 0.5 + math.random() * 2)
					TweenService:Create(body, TweenInfo.new(t, Enum.EasingStyle.Sine), { CFrame = home }):Play()
					task.wait(t + 1 + math.random() * 3)
				else
					task.wait(2 + math.random() * 3)
				end
			end
		end)
	end
end
