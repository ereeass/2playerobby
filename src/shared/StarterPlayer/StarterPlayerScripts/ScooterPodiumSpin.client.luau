--=====================================================================
-- ScooterPodiumSpin   (client)
--
-- The scooter on each lobby podium (its "Display", stood there by the server's
-- ScooterPodiums) turns slowly on the spot, like an item in a showcase. Only the
-- scooter turns: the pad, its glass case and the title stay put. It runs on each
-- player's machine, so the turn is perfectly smooth and costs the server nothing.
-- The axis is upright through the scooter's centre, which ScooterPodiums puts over
-- the pad's centre, so it stays centred all the way round. A display starts from
-- where it stands (no snap), also when it streams back in.
-- A podium with Still = true (a shop stand) keeps its scooter perfectly still instead;
-- only its glass moves: a soft glare (each pane's "Glint") slides across it now and then.
--=====================================================================

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local TURN_TIME = 10   -- seconds per full turn
local TAU       = 2 * math.pi
local RATE      = TAU / TURN_TIME

local displays = {}    -- [Display model] = its turn

local GLINT_TIME, GLINT_GAP = 1.4, 4.5   -- seconds a glare takes to cross, and between glares
local glints = {}      -- [UIGradient] = true

local function add(child)
	if child.Name == "Display" and child:IsA("Model") and child.Parent and child.Parent:GetAttribute("Still") then
		return   -- a still display: never turned
	end
	if child.Name == "Display" and child:IsA("Model") and not displays[child] then
		displays[child] = { angle = 0 }
	end
end

local function addGlint(d)
	if d:IsA("UIGradient") and d.Parent and d.Parent.Name == "Glint" then glints[d] = true end
end

local function watch(podium)
	for _, d in ipairs(podium:GetDescendants()) do addGlint(d) end
	podium.DescendantAdded:Connect(addGlint)
	podium.ChildAdded:Connect(add)
	local display = podium:FindFirstChild("Display")
	if display then add(display) end
end
CollectionService:GetInstanceAddedSignal("ScooterPodium"):Connect(watch)
for _, podium in ipairs(CollectionService:GetTagged("ScooterPodium")) do watch(podium) end

-- every part's place around the upright axis, as it stands; read on the display's
-- first frame here, once it has fully streamed in
local function capture(display, s)
	local parts = {}
	for _, d in ipairs(display:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then return false end
	local centre = CFrame.new(display:GetBoundingBox().Position)
	local offsets = {}
	for i, part in ipairs(parts) do offsets[i] = centre:ToObjectSpace(part.CFrame) end
	s.centre, s.parts, s.offsets, s.cframes = centre, parts, offsets, table.clone(offsets)
	s.pivot = centre:ToObjectSpace(display.WorldPivot)
	return true
end

RunService.RenderStepped:Connect(function(dt)
	-- the glass's glare: across, then a pause
	if next(glints) then
		local t = os.clock() % (GLINT_TIME + GLINT_GAP)
		local x = t < GLINT_TIME and (-1 + 2 * t / GLINT_TIME) or 1
		for g in pairs(glints) do
			if g.Parent then g.Offset = Vector2.new(x, 0) else glints[g] = nil end
		end
	end
	for display, s in pairs(displays) do
		if not display.Parent then
			displays[display] = nil   -- streamed out or replaced
		elseif s.parts or capture(display, s) then
			s.angle = (s.angle + RATE * dt) % TAU
			local turn = s.centre * CFrame.Angles(0, s.angle, 0)
			for i, offset in ipairs(s.offsets) do s.cframes[i] = turn * offset end
			workspace:BulkMoveTo(s.parts, s.cframes, Enum.BulkMoveMode.FireCFrameChanged)
			-- its pivot turns with it (BulkMoveTo leaves it), so its box stays centred
			display.WorldPivot = turn * s.pivot
		end
	end
end)
