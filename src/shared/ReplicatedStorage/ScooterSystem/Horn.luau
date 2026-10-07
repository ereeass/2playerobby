--=====================================================================
-- Horn   (ScooterSystem, on each player's machine)
--
-- The scooter horn. ONE path for every control: RideGui.Controller calls
-- Horn.Press / Horn.Release for the H key and for the touch button alike, and this
-- module does everything else.
--
--   Who     either rider honks their own scooter, and only while really on it. The
--           server decides whether they may (RideManager.ApplyInput) and marks it
--           on the scooter as the HornDriver / HornPassenger attributes.
--   Sound   every machine plays every scooter's horn itself, from that scooter's
--           Chassis: nearby players hear it, far ones don't (HornSound's roll-off),
--           and it goes when the scooter does. A scooter has ONE horn Sound per
--           machine, on while either rider honks, so two riders honking at once, or
--           the server echoing our own press back, can never double it. Our own
--           place is played from our own input at once; the server's word is used
--           for everyone else's.
--   Asset   94706203403618 is one short beep (0.165 s) repeated in groups with
--           pauses between, so it is never played whole. The beep is a two-tone
--           horn, 335.8 Hz and 418.6 Hz (measured with an AudioAnalyzer), almost
--           exactly 4:5, so both tones line up again every 11.93 ms. HornSound plays
--           the beep's own start (from 9 ms before it, so it answers at once), then
--           loops exactly that 11.93 ms from the middle of the beep for as long as
--           the horn is held: one steady, unbroken horn, not a string of beeps.
--           Measured: level steady to +-4 %, same tones as the beep, the loop seam
--           30 dB down. Letting go fades it out quickly; a tap still sounds for
--           MIN_ON, a short honk. Getting off, dying, or the scooter going cuts it
--           at once.
--
-- HornSound (in this module) holds the level, range and regions: tune them there.
-- SettingsController puts it in the SFX group, so the SFX volume slider applies.
--=====================================================================

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local RS              = game:GetService("ReplicatedStorage")

local Remotes  = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local template = script:WaitForChild("HornSound")
local player   = Players.LocalPlayer

local MIN_ON = 0.12    -- seconds: the shortest honk, so a quick tap still sounds like one
local FADE   = 0.06    -- seconds: a let-go horn fades out over this, so it never clicks

local Horn = {}
local changedEvent = Instance.new("BindableEvent")
Horn.Changed = changedEvent.Event    -- (held, available): for the touch button

---------------------------------------------------------------- this player
local role                -- "Driver" | "Passenger" while riding (RideGui.Controller)
local sources   = {}      -- [control] = true while held: "key" (H), "touch" (the button)
local held      = false   -- this player is sounding the horn
local available = false   -- ...and may: riding, on the scooter, alive
local ownScooter, ownRole -- the scooter and place of this player's latest ride
local horns     = {}      -- [scooter model] = its horn on this machine

-- the chassis this player stands on (RiderAttach's weld), while alive
local function myChassis()
	local ch   = player.Character
	local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	if not (hum and hum.Health > 0 and weld and weld.Part0) then return nil end
	return weld.Part0
end

local function setHeld(on)
	if on == held then return end
	held = on
	Remotes.DriveInput:FireServer({ Horn = on })
	changedEvent:Fire(held, available)
end

-- May this player honk right now? The moment they can't (off the scooter, dead,
-- the ride over), every control lets go and their horn stops at once.
local function refresh()
	local chassis = role and myChassis()
	if chassis then ownScooter, ownRole = chassis.Parent, role end
	local now = chassis ~= nil
	if now == available then return end
	available = now
	if not now then
		table.clear(sources)
		if held then
			held = false
			Remotes.DriveInput:FireServer({ Horn = false })
		end
		local h = ownScooter and horns[ownScooter]
		if h then h.cut = true end
	end
	changedEvent:Fire(held, available)
end

---------------------------------------------------------------- api
-- RideGui.Controller: this player's role while riding, nil once they are not
function Horn.SetRider(newRole)
	role = newRole
	refresh()
end

-- A control went down / came up. The horn sounds while any control holds it.
function Horn.Press(source)
	refresh()
	if not available then return end   -- walking, or not on a scooter: nothing
	sources[source] = true
	setHeld(true)
end

function Horn.Release(source)
	if not sources[source] then return end
	sources[source] = nil
	if next(sources) == nil then setHeld(false) end
end

-- every control let go at once (the window lost focus, say)
function Horn.ReleaseAll()
	table.clear(sources)
	setHeld(false)
end

function Horn.IsHeld() return held end
function Horn.IsAvailable() return available end

---------------------------------------------------------------- playback
-- Should this scooter's horn be on? Our own place follows our own input, never the
-- server's echo of it; the other rider's (and every other scooter) the server's word.
local function wanted(scooter)
	local function side(r)
		if scooter == ownScooter and r == ownRole then return held end
		return scooter:GetAttribute("Horn" .. r) == true
	end
	return side("Driver") or side("Passenger")
end

local function step(scooter, h, dt)
	local chassis = scooter.PrimaryPart
	if h.sound and h.sound.Parent ~= chassis then
		h.sound:Destroy()
		h.sound, h.playing = nil, false
	end
	if not chassis then return end          -- streamed out: too far away to hear anyway

	if wanted(scooter) then
		if not h.playing then
			if not h.sound then
				h.sound = template:Clone()
				h.sound.Parent = chassis
			end
			h.sound.TimePosition = template.PlaybackRegion.Min   -- just before the beep starts
			h.sound:Play()
			h.playing, h.since = true, os.clock()
		end
		-- held again while fading out: it carries straight on
		h.cut, h.fade = false, nil
		h.sound.Volume = template.Volume
	elseif h.playing then
		-- let go: a quick fade, once it has sounded for MIN_ON (cut: at once)
		if not h.fade and (h.cut or os.clock() - h.since >= MIN_ON) then h.fade = 0 end
		if h.fade then
			h.fade += dt
			local k = math.clamp(1 - h.fade / FADE, 0, 1)
			h.sound.Volume = template.Volume * k
			if k <= 0 then
				h.sound:Stop()
				h.sound.Volume = template.Volume
				h.playing, h.cut, h.fade = false, false, nil
			end
		end
	else
		h.cut = false
	end
end

local function track(scooter)
	if scooter:IsA("Model") and not horns[scooter] then horns[scooter] = { playing = false } end
end

task.spawn(function()
	local bin = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
	bin.ChildAdded:Connect(track)
	for _, s in ipairs(bin:GetChildren()) do track(s) end
	-- so the first honk doesn't wait for the download
	pcall(ContentProvider.PreloadAsync, ContentProvider, { template })
end)

RunService.Heartbeat:Connect(function(dt)
	if role or available then refresh() end
	for scooter, h in pairs(horns) do
		if scooter.Parent then
			step(scooter, h, dt)
		else
			if h.sound then h.sound:Destroy() end   -- the scooter went: its horn with it
			horns[scooter] = nil
		end
	end
end)

return Horn
