-- Other teams' scooters, and the players riding them, turn see-through when they are
-- close to you, so you can see where you are going while you pass through them (they
-- don't collide: ServerScriptService.ScooterSystem.CollisionGroups). On this client
-- only, through LocalTransparencyModifier, so nobody else's view changes. Your own
-- scooter and your partner never fade.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local GHOST     = 0.6    -- how see-through at the closest (0 solid, 1 invisible)
local NEAR      = 10     -- studs: fully faded inside this
local FAR       = 22     -- studs: fully solid beyond this
local FADE_RATE = 8      -- smoothing (higher = quicker)

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

-- [model] = { alpha, parts = {...} | nil }  -- parts cached until the model changes
local faded = {}

local function chassisOf(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local function entry(model)
	local e = faded[model]
	if not e then
		e = { alpha = 0 }
		faded[model] = e
		local function dirty() e.parts = nil end
		e.conns = { model.DescendantAdded:Connect(dirty), model.DescendantRemoving:Connect(dirty) }
	end
	return e
end

local function apply(model, e)
	if not e.parts then
		e.parts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then table.insert(e.parts, d) end
		end
	end
	for _, p in ipairs(e.parts) do p.LocalTransparencyModifier = e.alpha end
end

local function drop(model, e)
	e.alpha = 0
	if model.Parent then apply(model, e) end
	for _, c in ipairs(e.conns) do c:Disconnect() end
	faded[model] = nil
end

RunService.RenderStepped:Connect(function(dt)
	local myChar = player.Character
	local mine = chassisOf(myChar)
	local myScooter = mine and mine:FindFirstAncestorOfClass("Model")
	local ref = mine or (myChar and myChar:FindFirstChild("HumanoidRootPart"))

	-- who is close, and how close: each other scooter, and its riders with it
	local want = {}
	if ref then
		for _, s in ipairs(scooters:GetChildren()) do
			if s:IsA("Model") and s ~= myScooter and s.PrimaryPart then
				local d = (s.PrimaryPart.Position - ref.Position).Magnitude
				if d < FAR then
					want[s] = GHOST * math.clamp((FAR - d) / (FAR - NEAR), 0, 1)
				end
			end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			local ch = plr.Character
			local c = ch and plr ~= player and chassisOf(ch)
			local s = c and c:FindFirstAncestorOfClass("Model")
			if s and want[s] then want[ch] = want[s] end
			if s and not want[s] and s ~= myScooter then want[ch] = 0 end
		end
	end

	local k = 1 - math.exp(-FADE_RATE * dt)
	for model, target in pairs(want) do
		if target > 0 or faded[model] then
			local e = entry(model)
			e.alpha += (target - e.alpha) * k
			apply(model, e)
		end
	end
	-- anything no longer near (or gone, or no longer riding) eases back to solid
	for model, e in pairs(faded) do
		if not want[model] then
			if not model.Parent then
				for _, c in ipairs(e.conns) do c:Disconnect() end
				faded[model] = nil
			else
				e.alpha -= e.alpha * k
				if e.alpha < 0.01 then drop(model, e) else apply(model, e) end
			end
		elseif want[model] == 0 and e.alpha < 0.01 then
			drop(model, e)
		end
	end
end)
