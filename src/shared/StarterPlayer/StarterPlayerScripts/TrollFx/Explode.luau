--=====================================================================
-- Explode   (TrollFx) - EXPLODE PLAYERS, as this machine shows it
--
-- Rocket Launch without the rocket, on the scooter it was bought onto and nothing else: it
-- stops dead where it is and it builds - flashing red, the alarm's beeps coming faster and
-- faster, sparks and smoke leaking out, shaking harder and harder - then Rocket Launch's own
-- cartoon explosion goes off right there (TrollFx.Kit.explode: the same fireballs, ring,
-- smoke, sparks, stars, flying bits, BOOM! and sound), and they are gone. Nothing is launched:
-- the scooter never leaves its spot (it only trembles, on this screen). The alarm's sounds and
-- particles are the rocket booster's own (ReplicatedStorage.TrollFx.Booster). The clock is
-- ReplicatedStorage.TrollFx.ExplodeTimeline, from the server's start time.
--=====================================================================

local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local fx       = RS:WaitForChild("TrollFx")
local T        = require(fx:WaitForChild("ExplodeTimeline"))
local Kit      = require(fx:WaitForChild("Kit"))
local template = fx:WaitForChild("Booster")   -- only its sounds and emitters are borrowed

local MOUNT_Y  = -0.5    -- the underside of the deck (chassis space): where the alarm sits
local BOOM_UP  = 1.5     -- the explosion's middle, above the chassis (the riders' middles) - as the rocket's
local RED      = Color3.fromRGB(255, 40, 40)
local HOT      = Color3.fromRGB(255, 214, 90)

local Explode = {}

local shows = 0          -- each show's own name for its per-frame step

function Explode.Play(scooter)
	local start   = scooter:GetAttribute("TrollStart")
	local base    = scooter:GetAttribute("TrollBase")
	local chassis = scooter.PrimaryPart
	if not chassis then return end
	local function clock() return workspace:GetServerTimeNow() - start end

	local riders = Kit.ridersOf(scooter, chassis)
	local hidden = {}
	local pieces = {}          -- this machine's own additions, removed when it is over
	local function own(inst) table.insert(pieces, inst); return inst end
	local function cleanup()
		for _, inst in ipairs(pieces) do if inst.Parent then inst:Destroy() end end
		table.clear(pieces)
	end

	-- long over (this machine only just got here): the server has hidden it already
	if clock() >= T.EXPLODE + 1.5 then
		Kit.hide(scooter, hidden)
		for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
		return
	end

	local pivotFromChassis = chassis.CFrame:ToObjectSpace(scooter:GetPivot())

	-- the booster's alarm beep and the explosion, riding along with the scooter - only those two:
	-- none of its ignition or lift-off sounds (nothing takes off here)
	local speaker = own(Instance.new("Attachment"))
	speaker.Name = "TrollSpeaker"
	speaker.Parent = chassis
	local sounds = {}
	for _, s in ipairs(template.PrimaryPart:GetChildren()) do
		if s:IsA("Sound") and (s.Name == "Beep" or s.Name == "Boom") then
			local c = s:Clone()
			c.Parent = speaker
			sounds[s.Name] = c
		end
	end

	-- the alarm under the deck: a red light, sparks, and smoke leaking out (the booster's own)
	local exhaust = template.PrimaryPart:FindFirstChild("Exhaust")
	local alarm = own(Instance.new("Attachment"))
	alarm.Name = "TrollAlarm"
	alarm.Position = Vector3.new(0, MOUNT_Y, 0)
	alarm.Parent = chassis
	local light = Instance.new("PointLight")
	light.Color = RED
	light.Range = 16
	light.Brightness = 0
	light.Parent = alarm
	local sparks = exhaust.Sparks:Clone()
	sparks.Enabled = false
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Parent = alarm
	local smoke = exhaust.Smoke:Clone()
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.Rate = 0
	smoke.Enabled = true
	smoke.Parent = alarm

	-- the scooter and both riders glow red, flashing with each beep
	local glows = {}
	for _, m in ipairs({ scooter, table.unpack(riders) }) do
		local h = own(Instance.new("Highlight"))
		h.Adornee = m
		h.FillColor = RED
		h.OutlineColor = HOT
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = Kit.mine()
		table.insert(glows, h)
	end

	local colors = Kit.colorsOf(scooter)
	local played = {}
	local function once(name, fn)
		if played[name] then return end
		played[name] = true
		fn()
	end
	shows += 1
	local step = "TrollExplode" .. shows
	local nextBeep, flash = 0, 0
	local done = false

	local function finish()
		if done then return end
		done = true
		RunService:UnbindFromRenderStep(step)
	end

	-- every frame, before the cameras look at it
	local last = os.clock()
	RunService:BindToRenderStep(step, Enum.RenderPriority.Camera.Value - 1, function()
		local now = os.clock()
		local dt = math.min(now - last, 1 / 20)
		last = now
		if not (scooter.Parent and chassis.Parent) then finish() return end
		local t = clock()
		if t < 0 then return end

		if t >= T.EXPLODE then
			-- BOOM: the rocket's explosion, where it stands; the scooter and its riders are gone
			once("boom", function()
				scooter:PivotTo(base * pivotFromChassis)
				Kit.hide(scooter, hidden)
				for _, ch in ipairs(riders) do Kit.hide(ch, hidden) end
				for _, h in ipairs(glows) do h:Destroy() end
				light.Brightness = 0
				smoke.Rate = 0
				if t < T.EXPLODE + 1.5 then
					Kit.explode((base * CFrame.new(0, BOOM_UP, 0)).Position, sounds.Boom, colors)
				end
			end)
			finish()
			return
		end

		-- stopped dead where it is, shaking harder and harder
		scooter:PivotTo(T.Pose(base, t) * pivotFromChassis)
		local build = T.Build(t)

		-- the alarm: a beep and a red flash, faster and faster
		if t >= nextBeep then
			nextBeep = t + T.BeepGap(t)
			flash = 1
			if sounds.Beep then
				sounds.Beep.TimePosition = 0
				sounds.Beep:Play()
			end
			sparks:Emit(4 + math.floor(10 * build))
		end
		flash = math.max(flash - dt * 7, 0)
		local glow = math.max(flash, 0.25 * build)
		light.Brightness = 1 + 7 * glow
		for _, h in ipairs(glows) do
			h.FillTransparency = 1 - 0.65 * glow
			h.OutlineTransparency = 1 - glow
		end
		smoke.Rate = 4 + 26 * build
	end)

	-- when the scooter goes (the ride ended, or a revive brought a new one), so does
	-- everything this machine added; anyone still riding it is shown again
	local conn
	conn = scooter.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		conn:Disconnect()
		finish()
		Kit.unhide(hidden)
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

return Explode
