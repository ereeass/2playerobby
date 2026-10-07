-- The teleport poof inside the capsule booths. Purely visual, on every client:
-- when a team launches, the server (ServerScriptService.ScooterSystem.RideManager.
-- Begin) sends each rider's position through Remotes.TeleportFx and moves them
-- `lead` seconds later. Meanwhile, in the booth:
--   1. a soft mist gathers round the rider over that lead,
--   2. it bursts in one poof the moment they are moved, so they vanish inside it,
--   3. and thins away in the empty booth.
-- The textures are Roblox's built-in ones the map already uses: the campfire's
-- smoke and the waterfall's mist sparkles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local Remotes = ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local remote  = Remotes:WaitForChild("TeleportFx")

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"     -- as the campfire smoke
local GLINT_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"  -- as the waterfall mist
local MIST_COLOR    = Color3.fromRGB(222, 232, 250)
local GLINT_COLOR   = Color3.fromRGB(235, 245, 255)

local BODY_SIZE    = Vector3.new(3.2, 5.4, 3.2) -- the column the mist wraps round (one player, in a booth)
local DEFAULT_LEAD = 0.45                       -- if the server does not say
local GATHER_STEP  = 0.075                      -- seconds between the gathering wisps
local POOF_EARLY   = 0.05                       -- the poof starts this much before the move, so it
                                                -- is already there when the rider disappears
local MAX_POOFS    = 4                          -- per event; the server sends one per rider
local MAX_VIEW     = 300                        -- studs; further away nobody could see it
local LINGER       = 1.5                        -- seconds the part stays after the poof

local folder = Instance.new("Folder")
folder.Name = "TeleportFx"
folder.Parent = workspace

local function seq(points)
	local kps = {}
	for _, p in ipairs(points) do table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(kps)
end

local function smokeEmitter(name)
	local e = Instance.new("ParticleEmitter")
	e.Name           = name
	e.Texture        = SMOKE_TEXTURE
	e.Color          = ColorSequence.new(MIST_COLOR)
	e.LightEmission  = 0.35
	e.LightInfluence = 0.5
	e.Rotation       = NumberRange.new(0, 360)
	e.Shape          = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle     = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut     = Enum.ParticleEmitterShapeInOut.Outward
	e.Rate           = 0
	return e
end

-- slow wisps that hug the body and curl upward while the teleport charges
local function gatherEmitter()
	local e = smokeEmitter("Gather")
	e.Size         = seq({ { 0, 1 }, { 0.4, 2.4 }, { 1, 3 } })
	e.Transparency = seq({ { 0, 1 }, { 0.25, 0.45 }, { 0.6, 0.6 }, { 1, 1 } })
	e.Lifetime     = NumberRange.new(0.6, 0.9)
	e.Speed        = NumberRange.new(0.4, 1.2)
	e.Drag         = 1
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.RotSpeed     = NumberRange.new(-60, 60)
	return e
end

-- the poof itself: a quick outward burst, held in by drag so it fills the booth
local function poofEmitter()
	local e = smokeEmitter("Poof")
	e.Size         = seq({ { 0, 1.6 }, { 0.3, 3.2 }, { 1, 4 } })
	e.Transparency = seq({ { 0, 0.3 }, { 0.4, 0.55 }, { 1, 1 } })
	e.Lifetime     = NumberRange.new(0.5, 0.8)
	e.Speed        = NumberRange.new(3, 5.5)
	e.Drag         = 4
	e.Acceleration = Vector3.new(0, 2, 0)
	e.RotSpeed     = NumberRange.new(-40, 40)
	return e
end

-- a few faint glints rising through it
local function glintEmitter()
	local e = Instance.new("ParticleEmitter")
	e.Name           = "Glint"
	e.Texture        = GLINT_TEXTURE
	e.Color          = ColorSequence.new(GLINT_COLOR)
	e.LightEmission  = 1
	e.LightInfluence = 0
	e.Size           = seq({ { 0, 0.35 }, { 1, 0 } })
	e.Transparency   = seq({ { 0, 0.2 }, { 1, 1 } })
	e.Lifetime       = NumberRange.new(0.45, 0.75)
	e.Speed          = NumberRange.new(1.5, 3.5)
	e.Drag           = 2
	e.Acceleration   = Vector3.new(0, 4, 0)
	e.Shape          = Enum.ParticleEmitterShape.Box
	e.ShapeStyle     = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle    = Vector2.new(35, 35)
	e.Rate           = 0
	return e
end

local function poofAt(position, lead)
	local p = Instance.new("Part")
	p.Name = "Poof"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = BODY_SIZE
	p.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0))
	local gather, poof, glint = gatherEmitter(), poofEmitter(), glintEmitter()
	gather.Parent, poof.Parent, glint.Parent = p, p, p
	p.Parent = folder
	Debris:AddItem(p, lead + LINGER)

	-- 1. gathering: wisps come thicker and faster as the moment nears
	local steps = math.max(1, math.floor(lead / GATHER_STEP))
	for i = 0, steps - 1 do
		task.delay(i * GATHER_STEP, function()
			if gather.Parent then gather:Emit(2 + math.floor(3 * i / steps)) end
		end)
	end
	task.delay(lead * 0.5, function()
		if glint.Parent then glint:Emit(4) end
	end)
	-- 2. the poof, as the rider is moved away
	task.delay(math.max(0, lead - POOF_EARLY), function()
		if poof.Parent then poof:Emit(12) end
		if glint.Parent then glint:Emit(6) end
	end)
end

local function inView(position)
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - position).Magnitude < MAX_VIEW
end

remote.OnClientEvent:Connect(function(positions, lead)
	if type(positions) ~= "table" then return end
	lead = math.clamp(tonumber(lead) or DEFAULT_LEAD, 0.1, 1.5)
	for i, pos in ipairs(positions) do
		if i > MAX_POOFS then break end
		if typeof(pos) == "Vector3" and inView(pos) then poofAt(pos, lead) end
	end
end)
