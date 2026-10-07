--=====================================================================
-- FloatingBoards   (each player's own machine; looks only)
--
-- The lobby's Top Playtime and Fastest Duos boards float (no posts) and turn
-- to face this player's camera, easing round on the spot and bobbing gently.
-- Yaw only, so the boards stay upright (DonationBoardClient's HoverLift reads
-- the board part's live CFrame, so hover and clicks keep working). Only this
-- player's copy moves: the server's boards never change.
--=====================================================================

local RunService = game:GetService("RunService")

local BOARDS = { "playtime leaderboard", "Fastest Finish Leaderboard" }
local NEAR   = 160           -- studs: farther away a board isn't turned
local TURN   = 5             -- how quickly a board eases round to the camera
local BOB    = 0.25          -- studs up and down
local BOB_HZ = 0.35

local FACES = {
	Front = Enum.NormalId.Front, Back = Enum.NormalId.Back,
	Left = Enum.NormalId.Left, Right = Enum.NormalId.Right,
}

local boards = {}

local function flat(v)
	v = Vector3.new(v.X, 0, v.Z)
	return v.Magnitude > 1e-3 and v.Unit or nil
end

local function track(model, phase)
	-- the big Board part carries the list; its Face attribute says which side shows
	local main
	for _, p in ipairs(model:GetChildren()) do
		if p.Name == "Board" and p:IsA("BasePart") and p.Size.Y > 3 then main = p end
	end
	if not main then return end
	local normal = Vector3.FromNormalId(FACES[main:GetAttribute("Face") or "Back"] or Enum.NormalId.Back)
	local front = flat(main.CFrame:VectorToWorldSpace(normal))
	if not front then return end
	local box = model:GetBoundingBox()
	local base = model:GetPivot()
	table.insert(boards, {
		model = model,
		center = box.Position,
		rel = CFrame.new(box.Position):Inverse() * base,   -- the model's pivot from its centre
		front = front,
		yaw = 0,
		phase = phase,
	})
end

for i, name in ipairs(BOARDS) do
	task.spawn(function()
		local m = workspace:WaitForChild(name, 60)
		if m then
			-- the model is Persistent (always streamed in, as a whole); wait for its Board
			local t0 = os.clock()
			while not m:FindFirstChild("Board") and os.clock() - t0 < 30 do task.wait(0.5) end
			track(m, i * 1.7)
		end
	end)
end

local function signedYaw(from, to)
	return math.atan2(from:Cross(to).Y, from:Dot(to))
end

RunService.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	for _, b in ipairs(boards) do
		if b.model.Parent then
			local toCam = camPos - b.center
			if toCam.Magnitude < NEAR then
				local dir = flat(toCam)
				local want = dir and signedYaw(b.front, dir) or b.yaw
				local d = (want - b.yaw + math.pi) % (math.pi * 2) - math.pi
				b.yaw += d * math.min(1, TURN * dt)
				local lift = math.sin((now * BOB_HZ + b.phase) * math.pi * 2) * BOB
				b.model:PivotTo(CFrame.new(b.center + Vector3.yAxis * lift) * CFrame.Angles(0, b.yaw, 0) * b.rel)
			end
		end
	end
end)
