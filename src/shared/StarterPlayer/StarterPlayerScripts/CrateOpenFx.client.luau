--=====================================================================
-- CrateOpenFx   (StarterPlayerScripts)
--
-- A crate being opened (Remotes.CrateOpened, from ScooterSystem.Crates - the prize is
-- already the buyer's, chosen and saved by the server). Played on THIS client only, for the
-- buyer and for anyone near them:
--   Drop     the crate (ReplicatedStorage.CrateModels[crate.Model]) falls from above onto the
--            ground in front of the buyer, facing them, and lands with a squash. It is a
--            hologram: nothing collides with it or can touch it - walk straight through.
--   Charge   it spins faster and faster, grows and shakes, its light and sparks building.
--   Burst    a flash: the crate is gone.
--   Reveal   the scooter won (its visual copy, ScooterSystem.ScooterPreviews) pops out of the
--            light, turns for REVEAL_FOR seconds over a ring of its rarity's colour with its
--            name above it (a duplicate: and what it gave instead), then shrinks away.
--   Buyer    then gets "ADDED TO YOUR INVENTORY!" (a gift: "GIFT FROM <name>!"; a duplicate:
--            "DUPLICATE! +2 Revives") on screen.
-- Everything is this client's own (in a folder under the camera), made and removed per
-- opening: nothing is left behind, nothing replicates, nothing touches the ride system.
-- Openings for the same buyer play one after another. The buyer's own waits until they're
-- free in the lobby (like a gift's reveal); a buyer still riding after that just gets the message.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local RS                = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local Root     = RS:WaitForChild("ScooterSystem")
local Remotes  = Root:WaitForChild("Remotes")
local Shared   = require(Root:WaitForChild("Shared"):WaitForChild("Crates"))
local Scooters = require(Root:WaitForChild("Shared"):WaitForChild("Scooters"))
local HudSync  = require(RS:WaitForChild("HudSync"))

local SEE_RANGE   = 150     -- studs: openings further from this camera aren't shown
local AHEAD       = 12      -- studs in front of the buyer the crate lands
local SIDE        = 5       -- studs to the right of the buyer's own view (so they don't hide it)
local DROP_FROM   = 14      -- studs above the ground it falls from
local DROP_TIME   = 0.55
local CHARGE_TIME = 4
local WAIT_FREE   = 180     -- seconds the buyer's own opening waits for them to be free
local BURST_TIME  = 0.35
local REVEAL_FOR  = 4       -- seconds the scooter turns before it goes
local CRATE_SIZE  = 1.35    -- the crate drawn this much bigger than its model
local PRIZE_SIZE  = 1.3     -- the scooter drawn this much bigger than its menu copy
local GROW_TO     = 1.45    -- the crate's size at the end of the charge
local SPIN_MAX    = 720     -- degrees a second at the end of the charge
local RGB = Color3.fromRGB
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

local folder = Instance.new("Folder")
folder.Name = "CrateOpenings"
local function home()
	local cam = workspace.CurrentCamera
	if cam and folder.Parent ~= cam then folder.Parent = cam end
end
home()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(home)

--------------------------------------------------------------------- helpers
local function lerp(a, b, t) return a + (b - a) * t end
local function easeOut(t) return 1 - (1 - t) ^ 3 end
local function easeIn(t) return t * t end

-- a spring for the squash and pops: overshoots a little and settles
local function springScale(t, from, to)
	local w, z = 14, 0.35
	local e = math.exp(-z * w * t)
	return to + (from - to) * e * math.cos(w * math.sqrt(1 - z * z) * t)
end

local function sound(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.PlaybackSpeed = id, volume or 0.5, pitch or 1
	SoundService:PlayLocalSound(s)
	task.delay(4, function() s:Destroy() end)
end
-- the game's own sounds (the capsule door's thud, the freeze troll's shatter, Invite's chime)
local SND = {
	land   = "rbxassetid://9119202727",
	charge = "rbxassetid://6878476054",     -- (the black hole troll's hum) rises as it spins up
	burst  = "rbxassetid://9114855870",
	reveal = "rbxassetid://4612374036",
}

-- a model as a hologram: anchored, nothing can collide with it, touch it or hit it
local function hologram(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
			d.CastShadow = false
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
end

-- the ground under a point (characters, scooters and other openings ignored)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true
local function groundBelow(pos)
	local ignore = { folder }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore, p.Character) end end
	local scooters = workspace:FindFirstChild("RideSystem")
	if scooters then table.insert(ignore, scooters) end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

-- the line over the scooter: its name, and its rarity (or the duplicate's bonus)
local function nameTag(adornee, name, sub, color, parent)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(300, 84)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = SEE_RANGE
	bb.Adornee = adornee
	local function line(text, y, h, col, edge)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.FontFace = FONT
		l.Text = text
		l.TextColor3 = col
		l.TextScaled = true
		l.Position, l.Size = UDim2.fromScale(0, y), UDim2.fromScale(1, h)
		local s = Instance.new("UIStroke")
		s.Thickness, s.Color = edge, Color3.new(0, 0, 0)
		s.Parent = l
		l.Parent = bb
		return l
	end
	if sub ~= "" then
		line(name, 0, 0.56, Color3.new(1, 1, 1), 3)
		line(sub, 0.56, 0.4, color, 2.5)
	else
		line(name, 0.2, 0.6, Color3.new(1, 1, 1), 3)    -- just the scooter's name
	end
	bb.Parent = parent
	return bb
end

--------------------------------------------------------------------- one opening
local playing = {}   -- [buyer] = queue of openings

local function play(buyer, crateId, skinId, bonus, box, from)
	local c = Shared.Get(crateId)
	local prize = Shared.PrizeOf(crateId, skinId)
	local def = Scooters.Get(skinId)
	local mine = buyer == player
	local skinName = def and ((def.DisplayName or def.Id):upper()) or tostring(skinId)

	-- the message the buyer gets at the end (and alone, if there's nothing to show)
	local function tell()
		if not mine then return end
		local ok, Gift = pcall(function()
			return require(player:WaitForChild("PlayerGui"):WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Gift"))
		end)
		if not ok then return end
		if from and not bonus then
			Gift.fx.line("GIFT FROM " .. tostring(from):upper() .. "!", "Check your Skins to ride the " .. Gift.scooterName(def))
		elseif bonus then
			Gift.fx.line("DUPLICATE! " .. bonus:upper(), "You already had the " .. Gift.scooterName(def) .. " - check your inventory")
		else
			Gift.fx.line("ADDED TO YOUR INVENTORY!", "Check your Skins to ride the " .. Gift.scooterName(def))
		end
	end

	local ch = buyer.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	local riding = root and root:FindFirstChild("ScooterRiderWeld") ~= nil
	local busyMe = mine and (HudSync.InGame and HudSync.InGame())
	if not (c and root and cam) or riding or busyMe or (cam.CFrame.Position - root.Position).Magnitude > SEE_RANGE then
		tell()
		return
	end
	local template = RS:FindFirstChild("CrateModels") and RS.CrateModels:FindFirstChild(c.Model or "")
	local previews = Root:FindFirstChild("ScooterPreviews")
	local scooterTemplate = previews and previews:FindFirstChild(skinId)
	if not template then tell() return end

	-- where it lands: ahead of the buyer on the ground, facing them. For the buyer it is ahead
	-- of their CAMERA and a little to the right, so their own character never hides it.
	local look = (mine and cam.CFrame.LookVector or root.CFrame.LookVector) * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	look = look.Unit
	local right = look:Cross(Vector3.yAxis)
	local spot = root.Position + look * AHEAD + (mine and right * SIDE or Vector3.zero)
	local ground = groundBelow(spot)
	local toward = (mine and cam.CFrame.Position or root.Position) * Vector3.new(1, 0, 1) + Vector3.new(0, ground.Y, 0)
	local face = CFrame.lookAt(ground, toward)                -- its front toward the buyer / camera
	if (toward - ground).Magnitude < 0.1 then face = CFrame.lookAt(ground, ground - look) end

	local crate = template:Clone()
	hologram(crate)
	local size = crate:GetExtentsSize()
	local rest = face * CFrame.new(0, size.Y / 2, 0)         -- standing on the ground
	crate:PivotTo(rest + Vector3.new(0, DROP_FROM, 0))
	crate.Parent = box
	crate:ScaleTo(crate:GetScale() * CRATE_SIZE)
	size = crate:GetExtentsSize()
	rest = face * CFrame.new(0, size.Y / 2, 0)
	crate:PivotTo(rest + Vector3.new(0, DROP_FROM, 0))
	local baseScale = crate:GetScale()

	-- a glowing ring on the ground and a light, in the prize's rarity colour
	local color = prize and prize.Color or RGB(255, 170, 40)
	local ring = Instance.new("Part")
	-- on the ground: a soft light burst (the Shop's rays), slowly turning - not a solid disc
	ring.Name = "Ring"
	ring.Transparency = 1
	ring.Size = Vector3.new(11, 0.05, 11)
	ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0))
	hologram(ring)
	local rays = Instance.new("Decal")
	rays.Texture = "rbxassetid://101408805968103"
	rays.Face = Enum.NormalId.Top
	rays.Color3 = RGB(255, 236, 200)
	rays.Transparency = 1
	rays.Parent = ring
	ring.Parent = box
	local raysTurn = 0
	local function glow(a, dt)            -- a: 0 (gone) .. 1 (full); dt turns it
		rays.Transparency = 1 - 0.75 * a
		raysTurn += (dt or 0) * 25
		ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, math.rad(raysTurn), 0)
	end
	local lightPart = Instance.new("Part")
	lightPart.Transparency = 1
	lightPart.Size = Vector3.new(0.2, 0.2, 0.2)
	lightPart.CFrame = CFrame.new(ground + Vector3.new(0, 3, 0))
	hologram(lightPart)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = RGB(255, 170, 60), 14, 0
	light.Parent = lightPart
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(RGB(255, 220, 120), RGB(255, 120, 30))
	sparks.LightEmission, sparks.LightInfluence = 1, 0
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Parent = lightPart
	lightPart.Parent = box

	-- 1. the drop
	local t0 = os.clock()
	while true do
		local t = math.min((os.clock() - t0) / DROP_TIME, 1)
		crate:PivotTo(rest + Vector3.new(0, DROP_FROM * (1 - easeIn(t)), 0))
		glow(0.4 * t, 1 / 60)
		if t >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	sound(SND.land, 0.7, 1.1)
	local squashT0 = os.clock()
	while os.clock() - squashT0 < 0.35 do
		local s = springScale(os.clock() - squashT0, 0.8, 1)
		crate:ScaleTo(baseScale * s)
		crate:PivotTo(rest * CFrame.new(0, (s - 1) * size.Y / 2, 0))
		RunService.RenderStepped:Wait()
	end
	crate:ScaleTo(baseScale)

	-- 2. the charge: spin up, grow, shake, glow
	local hum = Instance.new("Sound")
	hum.SoundId, hum.Volume, hum.PlaybackSpeed, hum.Looped = SND.charge, 0.15, 0.7, true
	hum.RollOffMaxDistance = SEE_RANGE
	hum.Parent = lightPart
	hum:Play()
	local spin, lastTick = 0, 0
	t0 = os.clock()
	while true do
		local dt = RunService.RenderStepped:Wait()
		local t = math.min((os.clock() - t0) / CHARGE_TIME, 1)
		spin += SPIN_MAX * easeIn(t) * dt
		local s = lerp(1, GROW_TO, easeIn(t))
		local shake = 0.15 * t * t
		crate:ScaleTo(baseScale * s)
		crate:PivotTo(face * CFrame.new((math.random() - 0.5) * shake, size.Y * s / 2 + (math.random() - 0.5) * shake, 0)
			* CFrame.Angles(0, math.rad(spin), 0))
		light.Brightness = 4 * t
		sparks.Rate = 60 * t
		glow(0.4 + 0.4 * t, dt)
		hum.PlaybackSpeed = 0.7 + 0.9 * t
		hum.Volume = 0.15 + 0.45 * t
		if t >= 1 then break end
	end

	-- 3. the burst
	hum:Stop()
	sparks.Rate = 0
	sparks:Emit(40)
	sound(SND.burst, 0.7, 1)
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.new(1, 1, 1)
	flash.Size = Vector3.new(1, 1, 1)
	flash.CFrame = CFrame.new(ground + Vector3.new(0, size.Y * GROW_TO / 2, 0))
	hologram(flash)
	flash.Parent = box
	local parts = {}
	for _, d in ipairs(crate:GetDescendants()) do
		if d:IsA("BasePart") then parts[d] = d.Transparency end
	end
	t0 = os.clock()
	while true do
		local t = math.min((os.clock() - t0) / BURST_TIME, 1)
		flash.Size = Vector3.one * lerp(1, 12, easeOut(t))
		flash.Transparency = t
		crate:ScaleTo(baseScale * lerp(GROW_TO, GROW_TO * 1.4, t))
		for p, base in pairs(parts) do p.Transparency = lerp(base, 1, t) end
		light.Brightness = lerp(8, 3, t)
		if t >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	flash:Destroy()
	crate:Destroy()

	-- 4. the reveal: the scooter pops out of the light and turns
	rays.Color3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	light.Color = color
	local scooter
	if scooterTemplate then
		scooter = scooterTemplate:Clone()
		hologram(scooter)
		scooter.Parent = box
	end
	-- no name over the scooter (the owners' call): the buyer's message says it at the end
	sound(SND.reveal, 0.5, 1)
	local scooterBase = (scooter and scooter:GetScale() or 1) * PRIZE_SIZE
	local center = ground + Vector3.new(0, 3.6, 0)
	t0 = os.clock()
	local turn = 0
	while true do
		local dt = RunService.RenderStepped:Wait()
		local t = os.clock() - t0
		turn += 110 * dt
		local pop = t < 0.6 and math.max(springScale(t, 0.05, 1), 0.05) or 1
		local leave = t > REVEAL_FOR and math.max(1 - (t - REVEAL_FOR) / 0.35, 0.01) or 1
		if scooter then
			scooter:ScaleTo(scooterBase * pop * leave)
			scooter:PivotTo(CFrame.new(center + Vector3.new(0, math.sin(t * 2.2) * 0.25, 0)) * CFrame.Angles(0, math.rad(turn), 0))
		end
		light.Brightness = 3 * leave
		glow(leave, dt)
		if t > REVEAL_FOR and leave <= 0.01 then break end
	end
	if scooter then
		sparks.Color = ColorSequence.new(color)
		sparks:Emit(25)
		scooter:Destroy()
	end
	tell()
end

-- openings for the same buyer play one after another
local CrateShow = Remotes:WaitForChild("CrateShow")
Remotes:WaitForChild("CrateOpened").OnClientEvent:Connect(function(buyer, crateId, skinId, bonus, from, token)
	if typeof(buyer) ~= "Instance" or not buyer:IsA("Player") then return end
	if type(crateId) ~= "string" or type(skinId) ~= "string" then return end
	local q = playing[buyer]
	if type(from) ~= "string" then from = nil end
	if q then table.insert(q, { crateId, skinId, bonus, from, token }) return end
	q = {}
	playing[buyer] = q
	task.spawn(function()
		local job = { crateId, skinId, bonus, from, token }
		while job do
			-- the buyer's own opening waits until they're free in the lobby (the gift reveal's
			-- rule: no menu, not in a booth / riding / dead / a cutscene). It never interrupts
			-- anything; the prize is already theirs. Past WAIT_FREE it just plays (or, if they
			-- are riding, gives the message alone).
			if buyer == player then
				local ok, Gift = pcall(function()
					return require(player:WaitForChild("PlayerGui"):WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Gift"))
				end)
				local t0 = os.clock()
				while ok and Gift.fx.free and not Gift.fx.free() and player.Parent and os.clock() - t0 < WAIT_FREE do
					task.wait(0.25)
				end
			end
			-- now it plays for them: everyone else is shown it too (the server, with the token)
			if buyer == player and type(job[5]) == "string" then CrateShow:FireServer(job[5]) end
			-- each opening's pieces live in their own folder, removed when it ends - even if
			-- something went wrong part way (a second later, so the last sparks can finish)
			local box = Instance.new("Folder")
			box.Name = buyer.Name
			box.Parent = folder
			local ok, err = pcall(play, buyer, job[1], job[2], job[3], box, job[4])
			if not ok then warn("[CrateOpenFx] " .. tostring(err)) end
			task.delay(1, function() box:Destroy() end)
			job = table.remove(q, 1)
		end
		playing[buyer] = nil
	end)
end)
Players.PlayerRemoving:Connect(function(p) playing[p] = nil end)
