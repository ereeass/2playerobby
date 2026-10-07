--=====================================================================
-- Rocket   (TrollFx) - ROCKET LAUNCH, as this machine shows it
--
-- On the scooter it was bought onto, and nothing else: it stops dead, a red flash and beeps;
-- a rocket booster pops out from under it and stands it up on its nozzle; the booster catches,
-- smoke and sparks building to a roar; LIFT-OFF, straight up 100 studs, level, both riders on
-- board; a cartoon explosion at the top, and they are gone. Everything here is this machine's
-- own - the booster, the flames, the explosion, and the scooter's climb (the scooter and its
-- riders are only moved and hidden on this screen; on the server they never leave the road,
-- and the server hides them itself at the explosion). The clock is
-- ReplicatedStorage.TrollFx.RocketTimeline, from the server's start time, so every screen
-- shows the same moment. Look: ReplicatedStorage.TrollFx.Booster (restyle it in Explorer).
--=====================================================================

local RunService   = game:GetService("RunService")
local RS           = game:GetService("ReplicatedStorage")

local fx       = RS:WaitForChild("TrollFx")
local T        = require(fx:WaitForChild("RocketTimeline"))
local template = fx:WaitForChild("Booster")
local Kit      = require(fx:WaitForChild("Kit"))   -- the explosion and the pieces every show shares
local Config   = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Config"))

local MOUNT_Y  = -0.5    -- the booster's top: the underside of the deck (chassis space)
local BOOM_UP  = 1.5     -- the explosion's middle, above the chassis (the riders' middles)

local Rocket = {}

local shows = 0          -- each show's own name for its per-frame step
local mine, clamp01, ridersOf = Kit.mine, Kit.clamp01, Kit.ridersOf
local hide, unhide, seq, explode = Kit.hide, Kit.unhide, Kit.seq, Kit.explode

---------------------------------------------------------------- the show
function Rocket.Play(scooter)
	local start   = scooter:GetAttribute("TrollStart")
	local base    = scooter:GetAttribute("TrollBase")
	local chassis = scooter.PrimaryPart
	if not chassis then return end
	local function clock() return workspace:GetServerTimeNow() - start end

	local riders = ridersOf(scooter, chassis)
	local hidden = {}
	local pieces = {}          -- this machine's own additions, removed when it is over
	local function own(inst) table.insert(pieces, inst); return inst end
	local function cleanup()
		for _, inst in ipairs(pieces) do if inst.Parent then inst:Destroy() end end
		table.clear(pieces)
	end

	-- long over (this machine only just got here): the server has hidden it already
	if clock() >= T.EXPLODE + 1.5 then
		hide(scooter, hidden)
		for _, ch in ipairs(riders) do hide(ch, hidden) end
		return
	end

	local pivotFromChassis = chassis.CFrame:ToObjectSpace(scooter:GetPivot())
	-- how far the booster stands the scooter up: its nozzle rests on the ground
	local _, bsize = template:GetBoundingBox()
	local perch = math.max(bsize.Y - (Config.ScooterLift + MOUNT_Y), 0)

	-- the booster (hidden until it pops out), its emitters, and the sounds
	local booster = own(template:Clone())
	local mount = booster.PrimaryPart
	local exhaust = mount:FindFirstChild("Exhaust")
	local flame, core, smoke, sparks = exhaust.Flame, exhaust.Core, exhaust.Smoke, exhaust.Sparks
	local glow = exhaust.Glow
	local coreDisc = booster:FindFirstChild("Core")
	local speaker = own(Instance.new("Attachment"))   -- the sounds ride along with the scooter
	speaker.Name = "TrollSpeaker"
	speaker.Parent = chassis
	local sounds = {}
	for _, s in ipairs(mount:GetChildren()) do
		if s:IsA("Sound") then
			local c = s:Clone()
			c.Parent = speaker
			sounds[s.Name] = c
		end
	end
	local roarVolume = sounds.Roar and sounds.Roar.Volume or 0

	-- the alarm: a red flash under the deck, and sparks
	local alarm = own(Instance.new("Attachment"))
	alarm.Name = "TrollAlarm"
	alarm.Position = Vector3.new(0, MOUNT_Y, 0)
	alarm.Parent = chassis
	local alarmLight = Instance.new("PointLight")
	alarmLight.Color = Color3.fromRGB(255, 45, 45)
	alarmLight.Range = 14
	alarmLight.Brightness = 0
	alarmLight.Parent = alarm
	local alarmSparks = sparks:Clone()
	alarmSparks.EmissionDirection = Enum.NormalId.Bottom
	alarmSparks.Parent = alarm

	-- the ground under it: a cloud billowing out as the booster fires down at it
	local pad = own(Instance.new("Part"))
	pad.Anchored, pad.CanCollide, pad.CanTouch, pad.CanQuery = true, false, false, false
	pad.Transparency = 1
	pad.Size = Vector3.one * 0.2
	pad.CFrame = CFrame.new(base.Position - Vector3.new(0, Config.ScooterLift - 0.2, 0))
	pad.Parent = mine()
	local billow = smoke:Clone()
	billow.EmissionDirection = Enum.NormalId.Top
	billow.SpreadAngle = Vector2.new(82, 82)
	billow.Speed = NumberRange.new(9, 15)
	billow.Drag = 2.2
	billow.Size = seq({ { 0, 2 }, { 1, 7 } })
	billow.Parent = pad

	local colors = Kit.colorsOf(scooter)

	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	shows += 1
	local step = "TrollRocket" .. shows
	local nextSpark = 0
	local done = false

	local function finish()
		if done then return end
		done = true
		RunService:UnbindFromRenderStep(step)
	end

	-- every frame, before the cameras look at it
	RunService:BindToRenderStep(step, Enum.RenderPriority.Camera.Value - 1, function()
		if not (scooter.Parent and chassis.Parent) then finish() return end
		local t = clock()
		if t < 0 then return end

		if t >= T.EXPLODE then
			-- BOOM: the scooter, its riders and the booster are gone; the explosion is left
			once("boom", function()
				local cf = T.Pose(base, math.min(t, T.EXPLODE), perch)
				scooter:PivotTo(cf * pivotFromChassis)
				hide(scooter, hidden)
				for _, ch in ipairs(riders) do hide(ch, hidden) end
				if sounds.Roar then sounds.Roar:Stop() end
				booster:Destroy()
				billow.Rate = 0
				if t < T.EXPLODE + 1.5 then
					explode((cf * CFrame.new(0, BOOM_UP, 0)).Position, sounds.Boom, colors)
				end
			end)
			finish()
			return
		end

		-- the scooter (and, welded to it, both riders): up onto the booster, then the climb
		local cf = T.Pose(base, t, perch)
		scooter:PivotTo(cf * pivotFromChassis)

		-- the alarm
		if t < T.APPEAR then
			once("beep", function() if sounds.Beep then sounds.Beep:Play() end end)
			alarmLight.Brightness = (math.sin(t * 30) > 0) and 5 or 0
			if os.clock() >= nextSpark then
				nextSpark = os.clock() + 0.09
				alarmSparks:Emit(4)
			end
		else
			alarmLight.Brightness = 0
		end

		-- the booster pops out from under the deck
		if t >= T.APPEAR then
			once("appear", function()
				booster.Parent = mine()
				smoke:Emit(14)
				if sounds.Ignite then sounds.Ignite:Play() end
			end)
			if t <= T.APPEAR + T.POP + 0.05 then
				pcall(booster.ScaleTo, booster, math.max(0.25 + 0.75 * T.Pop(t), 0.05))
			else
				once("full size", function() pcall(booster.ScaleTo, booster, 1) end)
			end
			booster:PivotTo(cf * CFrame.new(0, MOUNT_Y, 0))
		end

		-- ignition building, then lift-off
		local ig = clamp01((t - (T.APPEAR + T.POP)) / (T.IGNITE_END - T.APPEAR - T.POP))
		local lift = T.Lift(t)
		if ig > 0 then
			once("roar", function()
				for _, e in ipairs({ flame, core, smoke, sparks }) do e.Enabled = true end
				billow.Enabled = true
				if sounds.Roar then
					sounds.Roar.Volume = 0
					sounds.Roar:Play()
				end
			end)
			flame.Rate  = 70 * ig + 90 * lift
			core.Rate   = 50 * ig + 60 * lift
			smoke.Rate  = 22 * ig + 40 * lift
			sparks.Rate = 24 * ig + 30 * lift
			billow.Rate = 32 * ig * (1 - clamp01(lift * 3))
			glow.Brightness = 2.5 * ig + 2 * lift
			if coreDisc then coreDisc.Transparency = 1 - math.max(ig, lift) end
			if sounds.Roar then sounds.Roar.Volume = roarVolume * (0.35 + 0.65 * ig) end
		end
		if t >= T.IGNITE_END then
			once("lift-off", function()
				if sounds.Launch then sounds.Launch:Play() end
				billow:Emit(34)
				flame.Size = seq({ { 0, 1.3 }, { 0.4, 2.4 }, { 1, 0.5 } })
			end)
		end
	end)

	-- when the scooter goes (the ride ended, or a revive brought a new one), so does
	-- everything this machine added; anyone still riding it is shown again
	local conn
	conn = scooter.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		conn:Disconnect()
		finish()
		unhide(hidden)
		cleanup()
	end)
	-- the explosion's pieces clean themselves up (Debris); the rest goes a little after it
	task.delay(math.max(start + T.END + 2 - workspace:GetServerTimeNow(), 0), function()
		for _, inst in ipairs(pieces) do
			if inst ~= speaker or not (sounds.Boom and sounds.Boom.IsPlaying) then
				if inst.Parent then inst:Destroy() end
			end
		end
	end)
end

return Rocket
