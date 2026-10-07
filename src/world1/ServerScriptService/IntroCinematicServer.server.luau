--=====================================================================
-- IntroCinematicServer   *** WORLD 1 ONLY ***
--
-- The server's two small jobs for World 1's intro cinematic (ReplicatedStorage.IntroCinematic):
--   * builds the classic bacon-hair avatar that plays the MOTOR, once, into
--     ReplicatedStorage.IntroCinematic.Bacon (every player's intro copies it on their machine)
--   * remembers who has seen the intro: HasSeenIntroCutscene in the player's save
--     (SettingsServer's PlayerData, server-only). The client can only ever ask "have I seen
--     it?" and say "I've seen it" - it can never set it back, so a replay never changes it.
--=====================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder  = ReplicatedStorage:WaitForChild("IntroCinematic")
local Config  = require(folder:WaitForChild("Config"))
if game.PlaceId ~= Config.PlaceId then return end   -- World 1 only

local remotes = folder:WaitForChild("Remotes")
local KEY     = Config.SeenKey

local dataApi
local function api()
	if dataApi then return dataApi end
	local settings = script.Parent:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 30)
	return dataApi
end

---------------------------------------------------------------- seen?
-- true = seen, false = never seen, nil = the save couldn't be read (then it doesn't auto-play)
remotes.IntroState.OnServerInvoke = function(player)
	local d = api()
	if not d then return nil end
	local ok, value, state = pcall(d.Get.Invoke, d.Get, player, KEY)
	if not ok or state == "failed" or state == "invalid" then return nil end
	return value == true
end

-- [player] = true: their first-join intro started on this server (IntroSeen): only then can its
-- end (IntroDone, below) count
local introStarted, introEnded = {}, {}

remotes.IntroSeen.OnServerEvent:Connect(function(player)
	introStarted[player] = true
	local d = api()
	if d then pcall(d.Set.Invoke, d.Set, player, KEY, true) end
end)

---------------------------------------------------------------- onboarding analytics
-- The first-join intro ended, watched or skipped (the client's IntroDone). Analytics only
-- (ScooterSystem.Funnels' onboarding "Got Through Cutscene"): counted once per player, only after
-- this server saw that same player's intro start; it changes nothing about the intro or the save.
local done = remotes:FindFirstChild("IntroDone")
if done then
	done.OnServerEvent:Connect(function(player)
		if not introStarted[player] or introEnded[player] then return end
		introEnded[player] = true
		task.spawn(function()
			local sys = game:GetService("ServerScriptService"):FindFirstChild("ScooterSystem")
			local ok, F = pcall(require, sys and sys:FindFirstChild("Funnels"))
			if ok and type(F) == "table" and type(F.IntroDone) == "function" then pcall(F.IntroDone, player) end
		end)
	end)
end
Players.PlayerRemoving:Connect(function(player) introStarted[player], introEnded[player] = nil, nil end)

---------------------------------------------------------------- the bacon
task.spawn(function()
	if folder:FindFirstChild("Bacon") then return end
	local b = Config.Bacon
	local desc = Instance.new("HumanoidDescription")
	desc.HairAccessory = tostring(b.Hair)
	desc.Shirt, desc.Pants = b.Shirt, b.Pants
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = b.Skin, b.Skin, b.Skin
	desc.TorsoColor, desc.LeftLegColor, desc.RightLegColor = b.Skin, b.Skin, b.Skin
	local model
	for _ = 1, 3 do
		local ok, m = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
		if ok and m then model = m break end
		task.wait(2)
	end
	if not model then warn("[Intro] couldn't build the bacon avatar") return end
	model.Name = "Bacon"
	-- the classic bacon look: Roblox now gives a default avatar a moving (dynamic) head, so it
	-- gets the classic round head (the engine's own Head shape) with the classic smile
	local head = model:FindFirstChild("Head")
	if head then
		for _, d in ipairs(head:GetChildren()) do
			if d:IsA("FaceControls") or d:IsA("Decal") then d:Destroy() end
		end
		head.Transparency = 1
		local k = head.Size.Y / 1.2
		local classic = Instance.new("Part")
		classic.Name = "ClassicHead"
		classic.Size = Vector3.new(2, 1, 1) * k
		classic.Color = b.Skin
		classic.CanCollide, classic.CanQuery, classic.CanTouch, classic.Massless = false, false, false, true
		classic.CFrame = head.CFrame
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Head
		mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
		mesh.Parent = classic
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = b.Face
		face.Parent = classic
		local weld = Instance.new("Weld")   -- (a Weld, like hats: it follows however the body is moved)
		weld.Part0, weld.Part1 = head, classic
		weld.Parent = classic
		classic.Parent = model
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = (d.Name == "HumanoidRootPart"); d.CanCollide = false end
	end
	model.Parent = folder
end)
