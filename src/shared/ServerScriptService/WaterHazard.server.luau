--=====================================================================
-- WaterHazard
--
-- The water under the course (Workspace.Map.Water) is the game's base death
-- hazard. Every part tagged "WaterHazard" is lethal, all alike; nothing else is
-- (the lobby pond, the fountain and any other blue part are decoration).
--
--   Hit    only during a scooter run: a rider, or their scooter, getting into the
--          water ends the run in the death popup (ScooterSystem.DeathManager).
--          Checked two ways so a long fall or a fast scooter can never slip
--          through: the water's own Touched, and every 0.1 s whether a rider's
--          root or a scooter is inside the water.
--   Home   anyone NOT in a run who is in the water is sent back to the lobby (no
--          death, no popup), so nobody is ever left stranded in the ocean - not
--          after falling off the lobby, and not after a run when a lagging machine
--          puts a character back where it was.
--   Size   a water part with a MatchBaseplate ObjectValue is fitted to that
--          part's footprint at start, so it follows the baseplate if it changes.
--          Only across (X/Z): its height and depth stay exactly where the water
--          was placed in the editor.
--   Rims   anything standing in the water (a pillar, a rock, an island) gets a
--          thin white rim where it meets the surface, made at start.
--
--=====================================================================

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))

local TAG         = "WaterHazard"
local DEPTH       = 8      -- studs of water on top of the baseplate
local CHECK_EVERY = 0.1    -- seconds between the inside-the-water checks
local RIM         = 0.6    -- width of the white rim round anything in the water
local RIM_THICK   = 0.2

local hazards  = {}        -- [water part] = true
local homeSent = {}        -- [player] = os.clock() of the last stranded-in-the-water send home
local HOME_AGAIN = 3       -- seconds before a stranded player is sent home again

---------------------------------------------------------------- the hit
-- One place for every water hit. Only a rider in a scooter run is affected
-- (DeathManager ignores anyone else, and each ride goes down only once).
local function onHazard(player)
	DeathManager.HitPlayer(player)
end

local function rideOfScooterPart(part)
	for scooter, ride in pairs(RideManager.Rides) do
		if part:IsDescendantOf(scooter) then return ride end
	end
	return nil
end

local function characterOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local player = Players:GetPlayerFromCharacter(model)
			if player then return player, model, humanoid end
			return nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function inside(water, position)
	local p = water.CFrame:PointToObjectSpace(position)
	local h = water.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

---------------------------------------------------------------- size
local function fit(water)
	local ref = water:FindFirstChild("MatchBaseplate")
	local base = ref and ref.Value
	if not (base and base:IsA("BasePart")) then return end
	-- the baseplate's footprint, at the height the water was placed at (it used to be
	-- moved down onto the baseplate, which dropped it far below where it was built)
	local y = water.Position.Y
	water.Size = Vector3.new(base.Size.X, water.Size.Y, base.Size.Z)
	water.CFrame = (base.CFrame - base.Position) + Vector3.new(base.Position.X, y, base.Position.Z)
end

---------------------------------------------------------------- white rims
-- A white slab just above the surface, the shape of the object where it meets
-- the water and RIM wider all round. The object hides the middle, so only a thin
-- rim shows, following its outline.
local function newRim(name)
	local rim = Instance.new("Part")
	rim.Name = name .. "Rim"
	rim.Anchored, rim.CanCollide, rim.CanQuery, rim.CanTouch = true, false, false, false
	rim.CastShadow = false
	rim.Material = Enum.Material.SmoothPlastic
	rim.Color = Color3.new(1, 1, 1)
	rim.TopSurface, rim.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return rim
end

-- the part's local axis that points (nearly) straight up, if any
local function upright(cf)
	if math.abs(cf.UpVector.Y) > 0.98 then return "Y" end
	if math.abs(cf.RightVector.Y) > 0.98 then return "X" end
	if math.abs(cf.LookVector.Y) > 0.98 then return "Z" end
	return nil
end

local function rimFor(part, surface)
	local c, size, cf = part.Position, part.Size, part.CFrame
	local y = surface + RIM_THICK / 2
	local isPart = part:IsA("Part")
	local rim = newRim(part.Name)

	if isPart and part.Shape == Enum.PartType.Ball then
		local r, dy = size.X / 2, surface - c.Y
		local d = 2 * math.sqrt(math.max(r * r - dy * dy, 0)) + 2 * RIM
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(RIM_THICK, d, d)
		rim.CFrame = CFrame.new(c.X, y, c.Z) * CFrame.Angles(0, 0, math.pi / 2)
		return rim
	end
	if isPart and part.Shape == Enum.PartType.Cylinder and upright(cf) == "X" then
		local d = math.min(size.Y, size.Z) + 2 * RIM
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(RIM_THICK, d, d)
		rim.CFrame = CFrame.new(c.X, y, c.Z) * CFrame.Angles(0, 0, math.pi / 2)
		return rim
	end

	-- everything else: its footprint where it crosses the surface, turned with it
	local axis = upright(cf)
	local a, b, la, lb
	if axis == "Y" then a, b, la, lb = cf.RightVector, cf.LookVector, size.X, size.Z
	elseif axis == "X" then a, b, la, lb = cf.UpVector, cf.LookVector, size.Y, size.Z
	elseif axis == "Z" then a, b, la, lb = cf.RightVector, cf.UpVector, size.X, size.Y
	else
		-- tilted: the flat outline of its whole box
		local ext = Vector3.new(
			math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
			0,
			math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z)
		a, b, la, lb = Vector3.xAxis, Vector3.zAxis, ext.X, ext.Z
	end
	local centre = c
	-- an upright wedge narrows towards its top: at the surface only the slice
	-- behind the slope is solid (the slope climbs from the front edge to the back)
	if part:IsA("WedgePart") and axis == "Y" then
		local t = math.clamp((surface - (c.Y - size.Y / 2)) / size.Y, 0, 1)
		local depth = size.Z * (1 - t)
		centre = c - cf.LookVector * ((size.Z - depth) / 2)
		lb = depth
	end
	a = Vector3.new(a.X, 0, a.Z).Unit
	b = Vector3.new(b.X, 0, b.Z).Unit
	rim.Size = Vector3.new(la + 2 * RIM, RIM_THICK, lb + 2 * RIM)
	rim.CFrame = CFrame.fromMatrix(Vector3.new(centre.X, y, centre.Z), a, Vector3.yAxis, -b)
	return rim
end

local function makeRims(water)
	local surface = water.Position.Y + water.Size.Y / 2
	local ref = water:FindFirstChild("MatchBaseplate")
	local folder = Instance.new("Folder")
	folder.Name = water.Name .. "Rims"
	local count = 0
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and not part:IsA("Terrain") and not hazards[part]
			and part ~= (ref and ref.Value) and part.Transparency < 0.95
			and not characterOf(part) and not part:FindFirstAncestorOfClass("Tool") then
			local cf, size = part.CFrame, part.Size
			local ext = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2
				+ math.abs(cf.LookVector.Y) * size.Z / 2
			-- crosses the surface, over the water
			if part.Position.Y - ext < surface and part.Position.Y + ext > surface
				and inside(water, Vector3.new(part.Position.X, water.Position.Y, part.Position.Z)) then
				local rim = rimFor(part, surface)
				rim.Parent = folder
				count += 1
			end
		end
	end
	folder.Parent = water.Parent
	return count
end

---------------------------------------------------------------- set up
local function addWater(water)
	if hazards[water] or not water:IsA("BasePart") then return end
	fit(water)
	hazards[water] = true
	water.Touched:Connect(function(hit)
		local player = characterOf(hit)
		if player then
			onHazard(player)
		else
			local ride = rideOfScooterPart(hit)
			if ride then DeathManager.Hit(ride) end
		end
	end)
	makeRims(water)
end

for _, water in ipairs(CollectionService:GetTagged(TAG)) do addWater(water) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(addWater)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(water) hazards[water] = nil end)
Players.PlayerRemoving:Connect(function(player) homeSent[player] = nil end)

-- the second check: a rider's root or a scooter inside the water, however it got there
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < CHECK_EVERY then return end
	elapsed = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if root and humanoid.Health > 0 then
			for water in pairs(hazards) do
				if inside(water, root.Position) then
					if RideManager.PlayerRide[player] then
						onHazard(player)
					elseif os.clock() - (homeSent[player] or 0) > HOME_AGAIN then
						homeSent[player] = os.clock()
						RideManager.SendHome(player)
					end
					break
				end
			end
		end
	end
	for _, ride in pairs(RideManager.Rides) do
		local chassis = not ride.Down and ride.Scooter and ride.Scooter.PrimaryPart
		if chassis then
			for water in pairs(hazards) do
				if inside(water, chassis.Position) then
					DeathManager.Hit(ride)
					break
				end
			end
		end
	end
end)
