-- Laser gates on the roads: every Model tagged "KillGate" (duplicate one anywhere, the
-- tag goes with it). Each gate is a grey frame across the road with two doorways,
-- DoorA and DoorB. Red lasers fill one doorway at a time:
--   * the lit doorway stays on for StayTime, then its lasers flicker for FlickerTime
--     (the other doorway blinks faintly, showing where they're going), then they swap.
--   * a scooter touching a lit laser ends that run in the death popup
--     (ScooterSystem.DeathManager: SKIP / REVIVE), like the water and the landmines.
--     A player on foot who touches one just dies. An unlit doorway is safe.
-- Per-gate attributes (on the gate Model):
--   StartSide   "A" or "B": which doorway is lit first               (default "A")
--   StayTime    seconds a doorway stays lit before flickering        (default 2.5)
--   FlickerTime seconds of flicker warning before they swap          (default 0.9)

local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local STAY_TIME    = 2.5
local FLICKER_TIME = 0.9
local FLICKERS     = 5
local LAMP_OFF     = Color3.fromRGB(70, 20, 20)

-- the ride (or on-foot player) behind whatever touched a laser
local function whoHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		if model.Parent == scooters then
			return RideManager.Rides[model], nil
		end
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			return RideManager.PlayerRide[plr], plr
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- the laser door sound, played from the laser when it kills (heard by whoever is nearby):
-- a short zap - it plays ZAP_LENGTH seconds, then fades out over ZAP_FADE
local ZAP_SOUND, ZAP_VOLUME = "rbxassetid://128069391098812", 0.12
local ZAP_LENGTH, ZAP_FADE = 0.6, 0.25
local function zap(laser)
	local s = Instance.new("Sound")
	s.SoundId = ZAP_SOUND; s.Volume = ZAP_VOLUME
	s.RollOffMode = Enum.RollOffMode.InverseTapered; s.RollOffMinDistance = 10; s.RollOffMaxDistance = 90
	s.Parent = laser
	s:Play()
	task.delay(ZAP_LENGTH, function()
		if s.Parent then
			game:GetService("TweenService"):Create(s, TweenInfo.new(ZAP_FADE), { Volume = 0 }):Play()
		end
	end)
	game:GetService("Debris"):AddItem(s, ZAP_LENGTH + ZAP_FADE + 0.05)
end

local function onTouched(hit, laser)
	local ride, plr = whoHit(hit)
	if ride then
		if not ride._ended and not ride.Down then
			DeathManager.Hit(ride)
			zap(laser)
		end
	elseif plr and plr.Character then
		local hum = plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = 0
			zap(laser)
		end
	end
end

local function arm(gate)
	if not gate:IsA("Model") then return end
	local doors = {}
	for _, side in ipairs({ "A", "B" }) do
		local door = gate:FindFirstChild("Door" .. side)
		if not door then
			warn("[KillGates] " .. gate:GetFullName() .. " has no Door" .. side)
			return
		end
		local d = { lasers = {}, lamps = {} }
		for _, p in ipairs(door:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "Laser" then
				table.insert(d.lasers, p)
				p.Touched:Connect(function(hit)
					if p.CanTouch and p.Transparency < 0.9 then onTouched(hit, p) end
				end)
			elseif p:IsA("BasePart") and p.Name == "Lamp" then
				table.insert(d.lamps, { part = p, on = p.Color })
			end
		end
		doors[side] = d
	end

	-- lit: deadly and bright. faint: the flicker preview on the other side, harmless.
	local function show(side, state)
		local d = doors[side]
		for _, laser in ipairs(d.lasers) do
			laser.CanTouch = state == "lit" or state == "dim"   -- the lit side stays deadly while it flickers
			laser.Transparency = (state == "lit" and 0) or (state == "dim" and 0.6) or (state == "faint" and 0.85) or 1
		end
		for _, lamp in ipairs(d.lamps) do
			local on = state == "lit" or state == "dim"
			lamp.part.Color = on and lamp.on or LAMP_OFF
			lamp.part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end

	local lit = gate:GetAttribute("StartSide") == "B" and "B" or "A"
	local function other(side) return side == "A" and "B" or "A" end
	show(lit, "lit")
	show(other(lit), "off")

	task.spawn(function()
		while gate.Parent do
			task.wait(gate:GetAttribute("StayTime") or STAY_TIME)
			if not gate.Parent then break end
			local blink = (gate:GetAttribute("FlickerTime") or FLICKER_TIME) / (FLICKERS * 2)
			for _ = 1, FLICKERS do
				show(lit, "dim")   show(other(lit), "faint")
				task.wait(blink)
				show(lit, "lit")   show(other(lit), "off")
				task.wait(blink)
			end
			lit = other(lit)
			show(lit, "lit")
			show(other(lit), "off")
		end
	end)
end

CollectionService:GetInstanceAddedSignal("KillGate"):Connect(arm)
for _, gate in ipairs(CollectionService:GetTagged("KillGate")) do arm(gate) end
