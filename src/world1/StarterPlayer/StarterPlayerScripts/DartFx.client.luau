-- Jungle Dirt Road dart shooters, drawn on THIS player's screen. The server
-- (Workspace > Jungle Dirt Road > Dart Shooters > DartShooterServer) decides hits; this
-- works out the same darts from the same shared clock and moves them smoothly, lights the
-- tiki's eyes up just before it fires, and plays a soft "pfft" when you're nearby.
-- Shooters are found by their "DartShooter" tag, whenever they stream in.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local SOUND_ID = "rbxassetid://106820392025820"
local VOLUME   = 0.35
local RANGE    = 80
local WARN     = 1.1                                   -- seconds of warning before each shot
local EYE_GROW = 0.6                                   -- eyes swell up to +60% as the shot nears
local EYE_DIM  = Color3.fromRGB(110, 20, 10)
local EYE_HOT  = Color3.fromRGB(255, 190, 60)

local player   = Players.LocalPlayer
local shooters = {}                                     -- [model] = state

local function add(m)
	if shooters[m] or not m:IsA("Model") then return end
	local muzzle, dart = m:FindFirstChild("Muzzle"), m:FindFirstChild("Dart")
	if not (muzzle and dart and dart.PrimaryPart) then return end
	local eyes = {}
	for _, p in ipairs(m:GetChildren()) do
		if p.Name == "Eye" and p:IsA("BasePart") then table.insert(eyes, { part = p, size = p.Size, cf = p.CFrame }) end
	end
	-- a glow at the pipe that flares up during the warning
	local glow = Instance.new("PointLight")
	glow.Color = EYE_HOT
	glow.Range = 10
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = muzzle
	local dartParts = {}
	for _, p in ipairs(dart:GetChildren()) do if p:IsA("BasePart") then table.insert(dartParts, p) end end
	local sound = Instance.new("Sound")
	-- a shooter may bring its own sound (the rainbow shooters do)
	sound.SoundId = m:GetAttribute("FireSound") or SOUND_ID
	sound.Volume = m:GetAttribute("FireVolume") or VOLUME
	sound.PlaybackSpeed = m:GetAttribute("FireSoundSpeed") or 1.7
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = RANGE
	sound.Parent = muzzle
	shooters[m] = { model = m, muzzle = muzzle, dart = dart, parts = dartParts, eyes = eyes, glow = glow, sound = sound, shot = nil, shown = false }
end

local function remove(m) shooters[m] = nil end

local function show(s, on)
	if s.shown == on then return end
	s.shown = on
	for _, p in ipairs(s.parts) do p.Transparency = on and 0 or 1 end
end

for _, m in ipairs(CollectionService:GetTagged("DartShooter")) do add(m) end
CollectionService:GetInstanceAddedSignal("DartShooter"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("DartShooter"):Connect(remove)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	for m, s in pairs(shooters) do
		if not m.Parent or not s.muzzle.Parent then shooters[m] = nil continue end
		local interval = m:GetAttribute("Interval") or 2.4
		local phase    = m:GetAttribute("Phase") or 0
		local speed    = m:GetAttribute("Speed") or 40
		local range    = m:GetAttribute("Range") or 13
		local t = now - phase
		local shot = math.floor(t / interval)
		local into = t - shot * interval
		-- warning: over the last WARN seconds the eyes heat up, swell and flash faster and
		-- faster, and the pipe glows, so the shot is easy to time
		local heat = math.clamp((into - (interval - WARN)) / WARN, 0, 1)
		local flash = 1
		if heat > 0 then
			local left = interval - into
			flash = 0.55 + 0.45 * math.cos(left * (6 + heat * 30))   -- blinks speed up near the shot
		end
		if into < 0.12 then heat, flash = 1, 1 end
		local lit = heat * flash
		for _, e in ipairs(s.eyes) do
			e.part.Color = EYE_DIM:Lerp(EYE_HOT, lit)
			e.part.Size = e.size * (1 + EYE_GROW * heat)
			e.part.CFrame = e.cf
		end
		s.glow.Brightness = 4 * lit
		-- the dart
		local flight = range / speed
		if into <= flight then
			s.dart:PivotTo(s.muzzle.CFrame * CFrame.new(0, 0, -into * speed))
			show(s, true)
			if s.shot ~= shot then
				s.shot = shot
				if root and (root.Position - s.muzzle.Position).Magnitude <= RANGE then s.sound:Play() end
			end
		else
			show(s, false)
		end
	end
end)
