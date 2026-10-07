-- Landmines on the course: every Model tagged "Landmine" (Workspace.Landmines; copy
-- and paste one anywhere, the tag goes with it). A scooter on a ride that rolls onto
-- one's invisible Trigger:
--   * blows it up: a flash, and the mine's own Boom sound. The driver's machine plays
--     that the instant its wheels touch (StarterPlayerScripts.LandmineFx); everyone
--     else is told through Remotes.LandmineBoom. The explosion is only a look - no
--     blast force - so nothing else nearby is moved.
--   * sends THAT scooter flying, tumbling, with both its riders still on it
--   * DEATH_DELAY later ends that run in the death popup (ScooterSystem.DeathManager:
--     SKIP / REVIVE), exactly like falling in the water. Only that ride.
-- The mine stays where it is for the next team: only the two riders see it vanish,
-- on their own screens, for a few seconds.

local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))

local LAUNCH_UP       = 200    -- studs/s straight up: about 100 studs high
local LAUNCH_BACK     = 25     -- studs/s thrown back the way it came
local SPIN            = 9      -- rad/s of tumble
local DEATH_DELAY     = 0.5    -- seconds of flight (the camera riding along) before the death popup; the water has none
local LAUNCH_HOLD     = 0.12   -- seconds the throw is kept up while the server takes the scooter over

local RunService = game:GetService("RunService")
local Remotes  = game:GetService("ReplicatedStorage"):WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local BoomFx   = Remotes:WaitForChild("LandmineBoom")
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local function boom(position)
	local ex = Instance.new("Explosion")
	ex.Position = position
	ex.BlastRadius = 8
	ex.BlastPressure = 0                 -- a look only: pushes nobody
	ex.DestroyJointRadiusPercent = 0     -- and breaks nothing
	ex.ExplosionType = Enum.ExplosionType.NoCraters
	ex.Parent = workspace

	-- a quick orange flash ball on top of Roblox's fireball
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored, flash.CanCollide, flash.CanTouch, flash.CanQuery = true, false, false, false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 150, 60)
	flash.Size = Vector3.one * 2
	flash.CFrame = CFrame.new(position)
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 16, Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)
end

-- this one scooter (and the riders welded to it) is thrown into the air, tumbling
local function launch(ride)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	if ride.Controller then
		pcall(function() ride.Controller:SetSteer(0); ride.Controller:SetThrottle("coast") end)
	end
	-- the server throws it, so the throw is the same on every screen
	pcall(function() chassis:SetNetworkOwner(nil) end)
	-- let go of the balance so it can tumble (see Shared.Balance)
	for _, name in ipairs({ "UprightAssist", "RollLock" }) do
		local c = chassis:FindFirstChild(name)
		if c then c.Enabled = false end
	end
	local back = -chassis.CFrame.LookVector
	local throw = Vector3.new(back.X * LAUNCH_BACK, LAUNCH_UP, back.Z * LAUNCH_BACK)
	local spin = chassis.CFrame.RightVector * SPIN + Vector3.new(0, (math.random() - 0.5) * SPIN, 0)
	-- the driver's machine keeps sending its last positions for a moment after the
	-- server takes over, which would eat the throw: keep it up until that has passed
	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if not chassis.Parent or t > LAUNCH_HOLD then conn:Disconnect(); return end
		chassis.AssemblyLinearVelocity = throw - Vector3.new(0, workspace.Gravity * t, 0)
		chassis.AssemblyAngularVelocity = spin
	end)
	chassis.AssemblyLinearVelocity = throw
	chassis.AssemblyAngularVelocity = spin
end

local function arm(mine)
	local trigger = mine:FindFirstChild("Trigger", true)
	if not trigger then
		warn("[Landmines] " .. mine:GetFullName() .. " has no Trigger part")
		return
	end
	trigger.Touched:Connect(function(hit)
		-- only a scooter that is on a live ride; walking players and anything else pass
		local scooter = hit:FindFirstAncestorOfClass("Model")
		while scooter and scooter.Parent ~= scooters do scooter = scooter:FindFirstAncestorOfClass("Model") end
		local ride = scooter and RideManager.Rides[scooter]
		-- each ride blows up once per life (a revive starts a new one): DeathManager.Claim
		local life = ride and DeathManager.Claim(ride)
		if not life then return end

		-- the sound on every machine that has not played it yet; the two riders also see
		-- the mine gone for a moment (LandmineFx), nobody else does
		local riders = {}
		if ride.Driver then table.insert(riders, ride.Driver) end
		if ride.Passenger then table.insert(riders, ride.Passenger) end
		BoomFx:FireAllClients(mine, riders)
		boom(trigger.Position)
		launch(ride)            -- thrown first, so the riders fly off with it
		-- the riders stay on the scooter, in one piece, through the blast and their death
		for _, handle in pairs(ride.Riders) do
			handle.KeepOnDeath = true
			if handle.Humanoid then handle.Humanoid.BreakJointsOnDeath = false end
		end
		task.delay(DEATH_DELAY, function() DeathManager.Hit(ride, mine, life) end)
	end)
end

CollectionService:GetInstanceAddedSignal("Landmine"):Connect(arm)
for _, mine in ipairs(CollectionService:GetTagged("Landmine")) do arm(mine) end

------------------------------------------------------------------ shuffled mines
-- Mines with a ShuffleGroup attribute (the stretch of Road3 by the crab island) get new
-- spots on server start, then again only while NO scooter is anywhere on Road 3 (so nobody
-- on that road ever sees them change mid-run). Every layout keeps
-- a smooth lane, wider than a scooter, free along the whole stretch, so it can always be
-- driven through. Spots are on the road's Deck planks, found along its centre line.
local LANE_HALF   = 3.6   -- half the free lane (a scooter is ~3 wide)
local MINE_R      = 1.1   -- a mine's trigger reach
local EDGE        = 1.2   -- kept off the road's edges
local LANE_DRIFT  = 0.3   -- how fast the lane may move sideways per stud along the road
local MINE_GAP    = 3     -- studs between mines
local RESHUFFLE   = 40    -- seconds between tries
local ON_ROAD_R   = 25    -- a scooter this close to any Road 3 part counts as on Road 3

local deckRay = RaycastParams.new()
deckRay.FilterType = Enum.RaycastFilterType.Include

local function setupGroup(mines)
	local built = workspace:FindFirstChild("Roads") and workspace.Roads:FindFirstChild("Road3")
	built = built and built:FindFirstChild("Built")
	if not built then return end
	-- the stretch: around the mines' own spots
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, m in ipairs(mines) do
		local p = m:GetPivot().Position
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local decks, line = {}, {}
	for _, d in ipairs(built:GetChildren()) do
		if d:IsA("BasePart") and (d.Name == "Deck" or d.Name == "DeckWedge") then
			table.insert(decks, d)
			local p = d.Position
			-- full-width planks are centred on the road: they give the centre line
			if d.Name == "Deck" and d.Size.X > 16.5 and p.X > lo.X - 12 and p.X < hi.X + 12 and p.Z > lo.Z - 12 and p.Z < hi.Z + 12 then
				table.insert(line, d)
			end
		end
	end
	if #line < 2 then return end
	deckRay.FilterDescendantsInstances = decks
	-- order the centre line along the road
	local dir = (hi - lo) * Vector3.new(1, 0, 1)
	table.sort(line, function(a, b) return a.Position:Dot(dir) < b.Position:Dot(dir) end)
	local pts, acc = {}, 0
	for i, d in ipairs(line) do
		if i > 1 then acc += (d.Position - line[i - 1].Position).Magnitude end
		table.insert(pts, { s = acc, cf = d.CFrame, half = d.Size.X / 2 })
	end
	local len = acc
	local offsets = {}
	for i, m in ipairs(mines) do
		-- how high each mine sits above the deck, and its lie
		local hit = workspace:Raycast(m:GetPivot().Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), deckRay)
		offsets[m] = hit and (m:GetPivot().Position.Y - hit.Position.Y) or 0.14
	end
	local function at(s, u)
		for i = 2, #pts do
			if s <= pts[i].s or i == #pts then
				local a, b = pts[i - 1], pts[i]
				local k = math.clamp((s - a.s) / math.max(b.s - a.s, 1e-3), 0, 1)
				local c = a.cf.Position:Lerp(b.cf.Position, k)
				local right = a.cf.RightVector:Lerp(b.cf.RightVector, k).Unit
				return c + right * u, math.min(a.half, b.half)
			end
		end
	end

	local function shuffle()
		-- the free lane: its centre wanders smoothly from one end to the other
		local laneAt = {}
		local step = 1
		local c = (math.random() - 0.5) * 6
		for s = 0, math.ceil(len), step do
			c = math.clamp(c + (math.random() - 0.5) * 2 * LANE_DRIFT * step, -4, 4)
			laneAt[s] = c
		end
		local placed = {}
		for _, m in ipairs(mines) do
			for _ = 1, 200 do
				local s = 1.5 + math.random() * math.max(len - 3, 0)
				local pos0, half = at(s, 0)
				local lim = half - EDGE
				local u = (math.random() * 2 - 1) * lim
				local lane = laneAt[math.floor(s)] or 0
				if math.abs(u - lane) >= LANE_HALF + MINE_R then
					local pos = at(s, u)
					local ok = true
					for _, q in ipairs(placed) do
						if (q - pos).Magnitude < MINE_GAP then ok = false break end
					end
					local hit = ok and workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), deckRay)
					if hit then
						table.insert(placed, pos)
						local rot = m:GetPivot().Rotation
						m:PivotTo(CFrame.new(hit.Position + Vector3.new(0, offsets[m], 0)) * rot)
						break
					end
				end
			end
		end
	end

	-- everything that makes up Road 3 (the road and its Road3 ... extras)
	local road3 = {}
	for _, r in ipairs(workspace.Roads:GetChildren()) do
		if r.Name == "Road3" or r.Name:sub(1, 6) == "Road3 " then table.insert(road3, r) end
	end
	local roadQuery = OverlapParams.new()
	roadQuery.FilterType = Enum.RaycastFilterType.Include
	roadQuery.FilterDescendantsInstances = road3
	roadQuery.MaxParts = 1
	local function scooterNear()
		for _, sc in ipairs(scooters:GetChildren()) do
			local pp = sc:IsA("Model") and sc.PrimaryPart
			if pp and #workspace:GetPartBoundsInRadius(pp.Position, ON_ROAD_R, roadQuery) > 0 then return true end
		end
		return false
	end
	shuffle()
	task.spawn(function()
		while true do
			task.wait(RESHUFFLE)
			if not scooterNear() then shuffle() end
		end
	end)
end

local groups = {}
for _, mine in ipairs(CollectionService:GetTagged("Landmine")) do
	local g = mine:GetAttribute("ShuffleGroup")
	if g then groups[g] = groups[g] or {}; table.insert(groups[g], mine) end
end
for _, mines in pairs(groups) do task.spawn(setupGroup, mines) end
