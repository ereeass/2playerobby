-- Everything cut into Road3's built road, in one place:
--   * the gap between nodes 3 and 4 (the plank bridge crosses it), with jagged ends
--   * three cracks bitten out of the road's edge (outer 4-5, inner by 5, outer by 6)
--
-- The RoadTools plugin rebuilds Road3 whenever a node moves, which wipes all cuts. So
-- the cuts are remembered against the build they were made on (Built's CutsFor =
-- BuiltFrom): ServerScriptService.Road3CutsRunner re-applies them when a game starts on
-- a newer build, and Apply() can be run from the command bar after editing:
--   require(game.ServerScriptService.Road3Cuts).Apply()
-- Node positions are read from Built's BuiltFrom record, so this works in a live game
-- after the node handles have been removed.

local Road3Cuts = {}
local rad = math.rad

-- node positions from the build record ("name:x,y,z,...|...")
local function nodesOf(built)
	local nodes = {}
	for entry in string.gmatch(built:GetAttribute("BuiltFrom") or "", "[^|]+") do
		local name, x, y, z = string.match(entry, "^(%d+):([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
		if name then nodes[tonumber(name)] = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
	end
	return nodes
end

local function cutter(built)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { built }
	return function(negs)
		for _, n in ipairs(negs) do n.Anchored = true n.CanCollide = false n.Transparency = 1 n.Parent = workspace end
		local targets = {}
		for _, n in ipairs(negs) do
			for _, p in ipairs(workspace:GetPartsInPart(n, params)) do targets[p] = true end
		end
		for p in pairs(targets) do
			if p.Parent then
				local ok, u = pcall(function()
					return p:SubtractAsync(negs, Enum.CollisionFidelity.PreciseConvexDecomposition, Enum.RenderFidelity.Precise)
				end)
				if ok and u and u.Size.Magnitude > 0.05 then
					u.Name = p.Name u.UsePartColor = true u.Color = p.Color
					u.Material = p.Material u.MaterialVariant = p.MaterialVariant
					u.Anchored = true u.CanCollide = p.CanCollide
					u.Parent = p.Parent
				end
				p:Destroy()
			end
		end
		for _, n in ipairs(negs) do n:Destroy() end
	end
end

local function neg(size, cf)
	local n = Instance.new("Part") n.Size = size n.CFrame = cf return n
end

---------------------------------------------------------------- apply everything
function Road3Cuts.Apply()
	local road = workspace:FindFirstChild("Roads") and workspace.Roads:FindFirstChild("Road3")
	local built = road and road:FindFirstChild("Built")
	if not built then return false, "no Road3.Built" end
	local nodes = nodesOf(built)
	for _, i in ipairs({ 2, 3, 6 }) do
		if not nodes[i] then return false, "node " .. i .. " missing from the build record" end
	end
	local cut = cutter(built)
	local rng = Random.new(3)

	-- the U-turn: a half circle from node 2 round to node 6
	local R = (nodes[2].X - nodes[6].X) / 2
	local C = Vector3.new(nodes[2].X - R, 0, nodes[2].Z)
	local function roadY(theta)
		return nodes[3].Y + (nodes[6].Y - nodes[3].Y) * math.clamp((theta - 45) / 135, 0, 1)
	end
	local function at(theta, off)
		local t = rad(theta)
		local p = C + Vector3.new(math.cos(t), 0, -math.sin(t)) * (R + off)
		return Vector3.new(p.X, roadY(theta), p.Z), Vector3.new(-math.sin(t), 0, -math.cos(t))
	end
	local function thetaOf(p)
		local d = Vector3.new(p.X - C.X, 0, p.Z - C.Z)
		local t = math.deg(math.atan2(-d.Z, d.X))
		if t < -90 then t += 360 end
		return t, d.Magnitude
	end

	-- 1) the gap from node 3 to node 4
	local G0, G1 = 48, 87
	for _, p in ipairs(built:GetChildren()) do
		if p:IsA("BasePart") then
			local th, r = thetaOf(p.Position)
			if th > G0 and th < G1 and math.abs(r - R) < 14 then p:Destroy() end
		end
	end
	local edgeNegs = {}
	for _, e in ipairs({ { G0, -1 }, { G1, 1 } }) do
		for _, off in ipairs({ -7.5, -3.5, 0.5, 4.5, 8.5 }) do
			local depth = 1 + rng:NextNumber() * 3.5
			local dTheta = -e[2] * (depth / 2) / (R * math.pi / 180)
			local pos, tangent = at(e[1] + dTheta, off)
			table.insert(edgeNegs, neg(Vector3.new(4.6, 8, depth * 2), CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, rad(rng:NextInteger(-25, 25)), 0)))
		end
	end
	cut(edgeNegs)

	-- 2) cracks bitten out of the edge
	for _, c in ipairs({ { 112, 1 }, { 135, -1 }, { 178, 1 } }) do
		local negs = {}
		local bite = 4 + rng:NextNumber() * 2
		for _ = 1, 3 do
			local along = (rng:NextNumber() - 0.5) * 5
			local inward = bite * (0.5 + rng:NextNumber() * 0.5)
			local pos, tangent = at(c[1] + along / (R * math.pi / 180), c[2] * (9.3 - inward / 2 + 0.6))
			table.insert(negs, neg(Vector3.new(inward + 1.2, 8, 2.5 + rng:NextNumber() * 3), CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, rad(rng:NextInteger(-35, 35)), 0)))
		end
		cut(negs)
	end

	built:SetAttribute("CutsFor", built:GetAttribute("BuiltFrom"))
	return true
end

-- cuts missing because the road was rebuilt since?
function Road3Cuts.NeedsApply()
	local built = workspace:FindFirstChild("Roads") and workspace.Roads:FindFirstChild("Road3") and workspace.Roads.Road3:FindFirstChild("Built")
	return built ~= nil and built:GetAttribute("CutsFor") ~= built:GetAttribute("BuiltFrom")
end

return Road3Cuts
