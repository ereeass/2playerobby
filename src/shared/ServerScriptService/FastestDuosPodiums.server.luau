--=====================================================================
-- FastestDuosPodiums   (server)
--
-- The two podiums either side of the Fastest Duos board (Workspace["Fastest Duos
-- Podiums"]): the #1 duo's avatars, dancing, with their usernames and time on the
-- nameplates. LeftPodium holds the Driver of the #1 run (its nameplate's RoleSign is
-- the booth's Driver wheel), RightPodium the Motor (the pedal): the board's a / b.
--
-- Follows the board's own snapshot (ReplicatedStorage.FastestDuosSystem.BoardData,
-- published by FastestDuosLeaderboard), so it changes exactly when the board does:
-- a new #1 duo swaps the avatars; a faster time by the same duo only updates the text.
--
-- Avatars are built on the server (so everyone sees the same thing) as R15 rigs, so
-- every avatar can play the dances. One that is too big for its podium (a tall
-- avatar, huge accessories) is scaled down to fit (never below MIN_SCALE), never
-- removed; one whose avatar cannot be loaded stands as a default avatar, with the
-- right name. The two always dance different dances and change dance now and then.
--=====================================================================

local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunTime = require(ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("RunTime"))

local podiums   = workspace:WaitForChild("Fastest Duos Podiums")
local boardData = ReplicatedStorage:WaitForChild("FastestDuosSystem"):WaitForChild("BoardData")

local MAX_HEIGHT  = 6.2    -- studs an avatar may be tall on a podium
local MAX_WIDTH   = 4.0    -- and wide (the podium top is 4.3)
local MIN_SCALE   = 0.3    -- shrunk no further than this, however big it is
local DANCE_EVERY = 12     -- seconds between dance changes

-- Roblox's own R15 dances (the default Animate script's), usable in any game. In rows
-- of the three dances, so two picks 4 apart are always two DIFFERENT dances.
local DANCES = {
	"rbxassetid://507771019", "rbxassetid://507776043", "rbxassetid://507777268",
	"rbxassetid://507771955", "rbxassetid://507776720", "rbxassetid://507777451",
	"rbxassetid://507772104", "rbxassetid://507776879", "rbxassetid://507777623",
}

local slots = {}   -- [1] = left, [2] = right: { Podium, Stand, Plate, UserId, Avatar, Track, Gen }
for _, name in ipairs({ "LeftPodium", "RightPodium" }) do
	local podium = podiums:WaitForChild(name)
	local plate = podium:WaitForChild("Column"):WaitForChild("Nameplate"):WaitForChild("Panel")
	table.insert(slots, {
		Podium = podium, Stand = podium:WaitForChild("Top"):WaitForChild("Stand"),
		Name = plate:WaitForChild("PlayerName"), Time = plate:WaitForChild("Time"),
		Gen = 0,
	})
end

local function attempt(fn, ...)
	local ok, result
	for i = 1, 3 do
		ok, result = pcall(fn, ...)
		if ok then return true, result end
		if i < 3 then task.wait(i) end
	end
	return false, result
end

--------------------------------------------------------------------- avatars
local function build(userId)
	local ok, desc = attempt(Players.GetHumanoidDescriptionFromUserId, Players, userId)
	if not ok then
		warn(("[Podiums] Could not load %d's avatar (standing in a default one): %s"):format(userId, tostring(desc)))
		desc = Instance.new("HumanoidDescription")
	end
	-- their animation pack isn't used here (the podium plays its own dances, and the Animate
	-- script is removed), and some packs only make Roblox warn "should reference a Folder
	-- named R15Anim" while the avatar is built
	for _, field in ipairs({ "ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation",
		"MoodAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation" }) do
		pcall(function() desc[field] = 0 end)
	end
	local made, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not made then
		warn("[Podiums] Could not build an avatar: " .. tostring(model))
		return nil
	end
	return model
end

-- scale to fit the podium, then stand it on the podium facing out like the board
local function place(model, stand)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return false end

	local out = -stand.WorldCFrame.LookVector * Vector3.new(1, 0, 1)   -- the podium's Back face: towards the viewer
	model:PivotTo(CFrame.lookAt(Vector3.zero, out))
	local size = model:GetExtentsSize()   -- body AND accessories
	local fit = math.min(1, MAX_HEIGHT / size.Y, MAX_WIDTH / math.max(size.X, size.Z))
	fit = math.max(fit, MIN_SCALE)
	if fit < 0.999 then model:ScaleTo(model:GetScale() * fit) end

	-- centred on the podium, the soles of its feet on the top
	local sole = math.huge
	for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
		local foot = model:FindFirstChild(name)
		if foot then sole = math.min(sole, foot.Position.Y - foot.Size.Y / 2) end
	end
	if sole == math.huge then sole = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 end
	local target = stand.WorldPosition
	local move = Vector3.new(target.X - root.Position.X, target.Y - sole, target.Z - root.Position.Z)
	model:PivotTo(model:GetPivot() + move)
	return true
end

local function setUp(model, userId)
	model.Name = "Avatar_" .. userId
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- the nameplate names them
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"   -- the rest hang on its joints, free to dance
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			d.Massless = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()   -- no Animate script: the dances are played from here
		end
	end
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
end

local animations = {}
for i, id in ipairs(DANCES) do
	local a = Instance.new("Animation")
	a.AnimationId = id
	animations[i] = a
end

-- A dance can hold a shrunk avatar a little off the ground (its moves are made for a
-- full-size rig): watch its feet for a moment and bring its lowest step down onto the
-- podium top.
local function settle(slot, track)
	task.wait(0.6)                                   -- past the blend into the dance
	local model = slot.Avatar
	if not model or slot.Track ~= track then return end
	local feet = { model:FindFirstChild("LeftFoot"), model:FindFirstChild("RightFoot") }
	if not (feet[1] and feet[2]) then return end
	local low = math.huge
	for _ = 1, 40 do
		for _, f in ipairs(feet) do low = math.min(low, f.Position.Y - f.Size.Y / 2) end
		task.wait(0.05)
	end
	if slot.Avatar ~= model or slot.Track ~= track or low == math.huge then return end
	local drop = low - slot.Stand.WorldPosition.Y
	if math.abs(drop) > 0.03 then model:PivotTo(model:GetPivot() - Vector3.new(0, drop, 0)) end
end

-- A dance Roblox won't load here ("Failed to load animation") is never tried again on this
-- server: each failed try is one more line in the game's Error Report (on the server, and on
-- every player's client the track is sent to). With none left, the avatars just stand.
local BAD_CHECK = 5   -- seconds after starting: a dance that loaded has a length by then
local bad = {}        -- [index] = true
local function goodDance(index)
	for i = 0, #DANCES - 1 do
		local k = ((index - 1 + i) % #DANCES) + 1
		if not bad[k] then return k end
	end
	return nil
end

-- Each avatar loads each dance ONCE and reuses its track (slot.Tracks): loading a fresh track
-- every DANCE_EVERY seconds piled up hundreds per avatar (Roblox's limit is 64 per Animator),
-- growing the server's memory and failing loads on the server and every client.
local function dance(slot, index)
	local model = slot.Avatar
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	index = goodDance(index)
	if not index then return end
	slot.Tracks = slot.Tracks or {}
	local track = slot.Tracks[index]
	if track and slot.Track == track then return end   -- already dancing this one
	if not track then
		local ok, loaded = pcall(animator.LoadAnimation, animator, animations[index])
		if not ok then bad[index] = true return end
		track = loaded
		slot.Tracks[index] = track
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		task.delay(BAD_CHECK, function()
			if track.Length == 0 then
				bad[index] = true
				print("[Podiums] dance " .. DANCES[index] .. " didn't load; not trying it again")
				if slot.Track == track then track:Stop(0) end
			end
		end)
	end
	track:Play(0.4)
	if slot.Track and slot.Track ~= track then slot.Track:Stop(0.4) end
	slot.Track = track
	slot.Dance = index
	task.spawn(settle, slot, track)
end

-- the slot shows this player (or nobody, with userId nil)
local function show(slot, userId)
	if slot.UserId == userId then return end
	slot.UserId = userId
	slot.Gen += 1
	local gen = slot.Gen
	if slot.Avatar then slot.Avatar:Destroy() end   -- its Animator, and every track on it, go with it
	slot.Avatar, slot.Track, slot.Tracks = nil, nil, {}
	if not userId then return end

	local model = build(userId)
	if not model or slot.Gen ~= gen then   -- failed, or #1 changed again while it loaded
		if model then model:Destroy() end
		return
	end
	setUp(model, userId)
	model.Parent = slot.Podium
	if not place(model, slot.Stand) then model:Destroy() return end
	slot.Avatar = model
	dance(slot, slot.Dance or (slot == slots[1] and 1 or 2))
end

--------------------------------------------------------------------- board
local function update()
	local ok, data = pcall(HttpService.JSONDecode, HttpService, boardData.Value)
	local first = ok and type(data) == "table" and type(data.duos) == "table" and data.duos[1]
	local a = first and tonumber(first.a)
	local b = first and tonumber(first.b)
	if not (a and b and tonumber(first.t)) then
		for _, slot in ipairs(slots) do
			slot.Name.Text = "---"
			slot.Time.Text = "Be the first!"
			task.spawn(show, slot, nil)
		end
		return
	end
	local time = "#1  " .. RunTime.Format(tonumber(first.t))
	slots[1].Name.Text, slots[2].Name.Text = tostring(first.an or "Player"), tostring(first.bn or "Player")
	slots[1].Time.Text, slots[2].Time.Text = time, time
	task.spawn(show, slots[1], a)
	task.spawn(show, slots[2], b)
end
boardData.Changed:Connect(update)
update()

-- a new dance every so often; the two never dance the same one
task.spawn(function()
	local step = 0
	while true do
		task.wait(DANCE_EVERY)
		step += 1
		local left = (step % #DANCES) + 1
		local right = ((step + 4) % #DANCES) + 1
		if slots[1].Avatar then dance(slots[1], left) else slots[1].Dance = left end
		if slots[2].Avatar then dance(slots[2], right) else slots[2].Dance = right end
	end
end)
