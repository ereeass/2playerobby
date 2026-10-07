--=====================================================================
-- BoothGuide   (each player's own machine)
--
-- A trail of glowing golden chevrons, with glints drifting alongside, on the ground leading a
-- player walking around the LOBBY to the booth they should go to:
--   1  a booth whose PARTNER is waiting (its station has exactly one of Driver / Motor
--      taken): the free booth of that station - the nearest such one in range
--   2  otherwise the nearest free booth of an empty station in range
-- Full stations (both taken) are never targets. Nothing is shown when no booth is within
-- MAX_GUIDANCE_DISTANCE, or when the player is standing at the door already.
--
-- Nothing here decides who is in a booth: occupancy is the server's - each booth model's
-- Occupied attribute (ServerScriptService.ScooterSystem.CapsuleEntry sets it as a player
-- walks in, TeamManager clears it the moment that role is free again: leaving, a
-- disconnect, a launch). This only reads it.
--
-- Shown ONLY while walking around the lobby. Hidden while:
--   in a booth / queued / counting down / riding     HudSync.InGame (StateChanged)
--   spectating a duo in the Troll window             HudSync.Aside
--   the loading screen or intro hasn't handed over   HudSync.WhenIntroDone
--   a cutscene                                       Cinematic.IsActive, or any script
--                                                    holding the camera (not Custom)
--   on a scooter, seated, dead, or no character
--   teleporting to another place
--   in a world it is off for                         ENABLED_WORLDS
--   too far from every booth                         MAX_GUIDANCE_DISTANCE
--
-- Purely visual and local: the arrows are parts only this player's machine has,
-- never collide, never block a raycast or a prompt, and nobody else sees them.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScooterSystem = ReplicatedStorage:WaitForChild("ScooterSystem")
local BoothEntrance = require(ScooterSystem:WaitForChild("Shared"):WaitForChild("BoothEntrance"))
local Cinematic     = require(ScooterSystem:WaitForChild("Cinematic"))
local HudSync       = require(ReplicatedStorage:WaitForChild("HudSync"))

---------------------------------------------------------------- settings (tune these)
local ENABLED_WORLDS        = { [1] = true, [2] = true }   -- WorldConfig.Id of each world it runs in
local MAX_GUIDANCE_DISTANCE = 50     -- studs (flat) from the player to a booth's door: farther booths are ignored
local RANGE_SLACK           = 6      -- a booth already shown stays until this much past the limit (no flicker at the edge)
local MAX_HEIGHT_DIFF       = 25     -- studs up/down: a booth far above or below doesn't count
local ARRIVE_DISTANCE       = 5      -- at the door already: the trail goes
local SWITCH_MARGIN         = 6      -- another booth of the same kind must be this much nearer to take over
local TARGET_FRONT          = BoothEntrance.FrontMin + 1.6   -- the spot to lead to: this far out in front of the glass

local SELECT_INTERVAL = 0.2          -- seconds between target checks (also re-checked at once on any booth change)
local SPACING         = 2.6          -- studs between chevrons
local START_GAP       = 2.5          -- first chevron this far ahead of the player
local FLOW_SPEED      = 5            -- studs a second the chevrons flow toward the booth
local EDGE_FADE       = 1.6          -- studs over which they grow in at the player and shrink away at the door
local MAX_CHEVRONS    = 30
local FADE_RATE       = 6            -- the whole trail grows in / shrinks away at this rate (1/s)
local TURN_RATE       = 10           -- how quickly the trail swings round to a new booth

-- one chevron: a glowing open chevron (cyan #3FE0FF, near-white toward the tip, thin #1A1A1A
-- outline; tip at the top of the image) laid flat on the ground, tip toward the booth. Cyan:
-- it stands out on the orange paths and matches the booths' cyan strips (owners, 2026-10-05)
local ARROW_IMAGE     = "rbxassetid://135170211247390"
local CHEVRON_WIDTH   = 3.1          -- the image's footprint
local CHEVRON_LENGTH  = 1.82
local LIFT            = 0.12         -- above the ground
local ARROW_LIGHT     = 0            -- painted-on glow: sun and shade don't dim it
local ARROW_BRIGHTNESS = 1.4         -- a little over 1, so the bloom gives it a soft glow

-- glints drifting toward the booth just beside the chevrons
local SPARKLE_OFFSET  = 1.7          -- studs out from the centre line, either side
local SPARKLE_IMAGE   = "rbxassetid://139017515112291"
local SPARKLES        = 1
local SPARKLE_SIZE    = 1.8          -- studs, at full size
local SPARKLE_SPEED   = 7            -- studs a second

---------------------------------------------------------------- world
local worldId = 1
do
	local ok, World = pcall(function() return require(ReplicatedStorage:WaitForChild("WorldConfig", 10)) end)
	if ok and type(World) == "table" and World.Id then worldId = World.Id end
end
if not ENABLED_WORLDS[worldId] then return end

local player = Players.LocalPlayer

---------------------------------------------------------------- lobby state
local introDone, teleporting = false, false
HudSync.WhenIntroDone(function() introDone = true end)
player.OnTeleport:Connect(function(state)
	teleporting = state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress
		or state == Enum.TeleportState.WaitingForServer
end)

-- the character's root and humanoid while walking about normally, else nil
local function walkingBody()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = hum and hum.RootPart
	if not (root and root.Parent) or hum.Health <= 0 then return nil end
	if hum.Sit or hum.PlatformStand or root:FindFirstChild("ScooterRiderWeld") then return nil end
	return root, hum
end

local function inLobby()
	if not introDone or teleporting then return false end
	if HudSync.Aside() then return false end          -- in a booth, queued, riding, or spectating
	if Cinematic.IsActive() then return false end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then return false end   -- a cutscene has the camera
	return true
end

---------------------------------------------------------------- booths (read only)
local stationsFolder = workspace:WaitForChild("RideSystem"):WaitForChild("CapsuleStations")
local ROLES = { "DriverCapsule", "MotorCapsule" }

local dirty = true                                  -- re-pick the target at the next step
local watched = setmetatable({}, { __mode = "k" })  -- [booth model] = true: its Occupied is listened to

-- A station's booth for one role, or nil while it can't be used (missing, streamed out,
-- being rebuilt): { model, door (Vector3, floor level, out in front of the glass), occupied }
local function boothOf(station, roleName)
	local trigger = station:FindFirstChild(roleName)
	local ref = trigger and trigger:FindFirstChild("CapsuleModel")
	local model = ref and ref:IsA("ObjectValue") and ref.Value
	if not (model and model:IsA("Model") and model:IsDescendantOf(workspace)) then return nil end
	if not watched[model] then
		watched[model] = true
		model:GetAttributeChangedSignal("Occupied"):Connect(function() dirty = true end)
	end
	local ok, pivot = pcall(function() return model.WorldPivot end)
	if not ok then return nil end
	return {
		model = model,
		door = pivot:PointToWorldSpace(Vector3.new(0, 0, -TARGET_FRONT)),
		occupied = model:GetAttribute("Occupied") == true,
	}
end

stationsFolder.ChildAdded:Connect(function() dirty = true end)
stationsFolder.ChildRemoved:Connect(function() dirty = true end)
Cinematic.Changed:Connect(function() dirty = true end)
HudSync.OnAside(function() dirty = true end)

-- Every booth worth going to, with whether its partner is waiting.
local function candidates()
	local list = {}
	for _, station in ipairs(stationsFolder:GetChildren()) do
		local a, b = boothOf(station, ROLES[1]), boothOf(station, ROLES[2])
		if a and b then                                  -- a station only counts whole
			local taken = (a.occupied and 1 or 0) + (b.occupied and 1 or 0)
			if taken == 1 then
				local free = a.occupied and b or a       -- the role nobody has: Driver or Motor
				table.insert(list, { booth = free, waiting = true })
			elseif taken == 0 then
				table.insert(list, { booth = a, waiting = false })
				table.insert(list, { booth = b, waiting = false })
			end                                          -- taken == 2: full, never a target
		end
	end
	return list
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

---------------------------------------------------------------- target selection
local target            -- the booth model being led to, or nil
local targetDoor        -- its door point

-- Step 1-5: in the lobby? which booths are valid and in range? waiting ones first, else
-- the nearest free one. Distance and priority are decided together: a waiting booth out
-- of range never beats a free one in range.
local function pickTarget(root)
	local pos = root.Position
	local best = { [true] = nil, [false] = nil }        -- nearest in range, per kind (waiting / not)
	local current
	for _, c in ipairs(candidates()) do
		local door = c.booth.door
		local d = flatDistance(pos, door)
		local limit = MAX_GUIDANCE_DISTANCE + ((c.booth.model == target) and RANGE_SLACK or 0)
		if d <= limit and math.abs(door.Y - pos.Y) <= MAX_HEIGHT_DIFF then
			c.distance = d
			local b = best[c.waiting]
			if not b or d < b.distance then best[c.waiting] = c end
			if c.booth.model == target then current = c end
		end
	end
	local pick = best[true] or best[false]
	if not pick then return nil end
	-- keep the current booth unless another of the same kind is clearly nearer
	if current and current.waiting == pick.waiting and current.distance - pick.distance < SWITCH_MARGIN then
		pick = current
	end
	return pick
end

---------------------------------------------------------------- chevrons
local folder = Instance.new("Folder")
folder.Name = "BoothGuideArrows"

-- an invisible flat part carrying the arrow image on its top face: { part, gui, image }
local function arrow()
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(CHEVRON_LENGTH, 0.05, CHEVRON_WIDTH)   -- (on a Top face the image runs along X)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top            -- the image's top edge (the tip) is the part's -X side
	gui.LightInfluence = ARROW_LIGHT
	gui.Brightness = ARROW_BRIGHTNESS
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.Enabled = false
	gui.Parent = p
	local img = Instance.new("ImageLabel")
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = ARROW_IMAGE
	img.Parent = gui
	p.Parent = folder
	return { part = p, gui = gui, image = img }
end

local chevrons = {}
for i = 1, MAX_CHEVRONS do chevrons[i] = arrow() end

-- a glint: an invisible point carrying a camera-facing sparkle
local function sparkle(i)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	local bb = Instance.new("BillboardGui")
	bb.LightInfluence = 0
	bb.Brightness = 2
	bb.Size = UDim2.fromScale(0, 0)
	bb.Enabled = false
	bb.Parent = p
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = SPARKLE_IMAGE
	img.Parent = bb
	p.Parent = folder
	return { part = p, gui = bb, phase = (i - 1) / SPARKLES, side = (i % 2 == 0) and 1 or -1 }
end
local sparkles = {}
for i = 1, SPARKLES do sparkles[i] = sparkle(i) end
local sparkleTime = 0

local parts, cframes = {}, {}
local PARKED = CFrame.new(0, -10000, 0)

-- Lays arrow `a` flat at `center` (ground level), tip along `forward`: the part's -X side
-- (the image's top) faces `forward`. It grows in and shrinks away by `scale`.
local function place(a, center, forward, right, scale)
	if a.scale ~= scale then
		a.scale = scale
		a.image.Size = UDim2.fromScale(scale, scale)
	end
	local up = Vector3.yAxis
	table.insert(parts, a.part); table.insert(cframes, CFrame.fromMatrix(center + up * LIFT, -forward, up, -right))
end

local function park(a)
	table.insert(parts, a.part); table.insert(cframes, PARKED)
end

-- Shown or not (the arrow grows in and shrinks away by `scale` in place, always solid).
local function setShown(a, on)
	if a.gui.Enabled ~= on then a.gui.Enabled = on end
end

local function smooth01(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end

---------------------------------------------------------------- run
local shown     = 0          -- 0..1, the whole trail's fade
local drawEnd                -- where the trail ends (eases toward the target's door)
local groundY                -- the player's feet, held while they're in the air
local flow      = 0
local nextPick  = 0

local function feetY(root, hum)
	if hum.RigType == Enum.HumanoidRigType.R6 then return root.Position.Y - 3 end
	return root.Position.Y - hum.HipHeight - root.Size.Y / 2
end

local visibleWanted = false
RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	local root, hum = walkingBody()
	local ok = root ~= nil and inLobby()

	-- target selection: a few times a second, and at once when a booth changes
	local now = os.clock()
	if not ok then
		target, targetDoor = nil, nil
	elseif dirty or now >= nextPick then
		dirty, nextPick = false, now + SELECT_INTERVAL
		local pick = pickTarget(root)
		if pick then
			if pick.booth.model ~= target then drawEnd = drawEnd or pick.booth.door end
			target, targetDoor = pick.booth.model, pick.booth.door
		else
			target, targetDoor = nil, nil
		end
	end
	if target and not target:IsDescendantOf(workspace) then target, targetDoor, dirty = nil, nil, true end

	visibleWanted = ok and targetDoor ~= nil and flatDistance(root.Position, targetDoor) > ARRIVE_DISTANCE
	-- out of the lobby (a booth, a ride, a cutscene...): gone at once; in and out of range
	-- or arriving at the door: a short fade
	shown = ok and math.clamp(shown + (visibleWanted and 1 or -1) * FADE_RATE * dt, 0, 1) or 0

	if shown <= 0 then
		if folder.Parent then folder.Parent = nil end
		drawEnd, groundY = nil, nil
		return
	end
	if not folder.Parent then folder.Parent = workspace end

	-- the path: the player's feet to the door, flat, easing round when the target changes
	if hum.FloorMaterial ~= Enum.Material.Air or not groundY then groundY = feetY(root, hum) end
	local goal = targetDoor or drawEnd
	if not goal then return end
	drawEnd = drawEnd and drawEnd:Lerp(goal, 1 - math.exp(-TURN_RATE * dt)) or goal
	local from = Vector3.new(root.Position.X, groundY, root.Position.Z)
	local flat = Vector3.new(drawEnd.X - from.X, 0, drawEnd.Z - from.Z)
	local length = flat.Magnitude
	if length < 1e-3 then return end
	local forward = flat / length
	local right = forward:Cross(Vector3.yAxis)

	flow = (flow + FLOW_SPEED * dt) % SPACING
	table.clear(parts); table.clear(cframes)
	local span = length - START_GAP
	for i, ch in ipairs(chevrons) do
		local along = START_GAP + flow + (i - 1) * SPACING
		if span > 0 and along <= length then
			local k = (along - START_GAP) / span           -- 0 at the player .. 1 at the door
			local y = groundY + (drawEnd.Y - groundY) * math.clamp(k, 0, 1)
			local center = Vector3.new(from.X, y, from.Z) + forward * along
			local edge = math.min(along - START_GAP, length - along) / EDGE_FADE
			local scale = smooth01(edge) * shown
			if scale > 0.05 then
				place(ch, center, forward, right, scale)
				setShown(ch, true)
			else
				park(ch)
				setShown(ch, false)
			end
		else
			park(ch)
			setShown(ch, false)
		end
	end
	-- the glints: along the same sloped path as the chevrons, from the first chevron's spot to
	-- the door
	local a = Vector3.new(from.X, groundY, from.Z) + forward * START_GAP
	local b = Vector3.new(drawEnd.X, drawEnd.Y, drawEnd.Z)
	local run3 = b - a
	local len3 = run3.Magnitude
	if span > 0.5 and len3 > 0.5 then
		local along3 = run3 / len3
		local up3 = right:Cross(along3)
		sparkleTime += dt
		for i, sp in ipairs(sparkles) do
			local k = ((sparkleTime * SPARKLE_SPEED) / len3 + sp.phase) % 1
			local pos = a + run3 * k + right * SPARKLE_OFFSET * sp.side + up3 * (LIFT + 0.2)
			local twinkle = 0.7 + 0.3 * math.sin(sparkleTime * 9 + i * 2.1)
			local size = SPARKLE_SIZE * math.sin(k * math.pi) * twinkle * shown
			sp.gui.Size = UDim2.fromScale(size, size)
			table.insert(parts, sp.part); table.insert(cframes, CFrame.new(pos))
			if not sp.gui.Enabled then sp.gui.Enabled = true end
		end
	else
		for _, sp in ipairs(sparkles) do park(sp); sp.gui.Enabled = false end
	end

	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)

player.CharacterRemoving:Connect(function() dirty = true end)
