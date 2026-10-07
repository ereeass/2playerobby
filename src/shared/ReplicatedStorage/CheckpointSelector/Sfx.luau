--=====================================================================
-- Sfx
--
-- The selector's sounds, played by name from the Sfx folder in
-- StarterGui.CheckpointSelectorGui: Open, Close, Hover, Click, Navigate,
-- Start. To use your own, change that Sound's SoundId / Volume in Explorer;
-- no asset id is written in code. They start as the game's existing UI
-- sounds (the Invite / Settings clicks, the Invite success chime and the
-- loading screen's air whooshes).
--
-- Optional attributes on each Sound:
--   Cooldown  seconds before it can play again, so fast clicking never stacks
--   Swell     fade in over Attack s and out over Release s instead of playing
--             through: this is how the air-whoosh loop becomes one soft
--             whoosh. StartAt is where in the file it begins.
--=====================================================================

local TweenService = game:GetService("TweenService")

local Sfx = {}
Sfx.__index = Sfx

function Sfx.new(folder)
	return setmetatable({ folder = folder, last = {}, peak = {}, tweens = {} }, Sfx)
end

function Sfx:play(name)
	local s = self.folder and self.folder:FindFirstChild(name)
	if not (s and s:IsA("Sound")) then return end
	local now = os.clock()
	if now - (self.last[name] or -math.huge) < (s:GetAttribute("Cooldown") or 0.05) then return end
	self.last[name] = now

	if not s:GetAttribute("Swell") then
		s.TimePosition = 0
		s:Play()
		return
	end

	local peak = self.peak[s] or s.Volume
	self.peak[s] = peak
	if self.tweens[s] then self.tweens[s]:Cancel() end
	s.Volume = 0
	s.TimePosition = s:GetAttribute("StartAt") or 0
	s:Play()
	local up = TweenService:Create(s, TweenInfo.new(s:GetAttribute("Attack") or 0.1,
		Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Volume = peak })
	self.tweens[s] = up
	up:Play()
	up.Completed:Once(function(state)
		if state ~= Enum.PlaybackState.Completed then return end
		local down = TweenService:Create(s, TweenInfo.new(s:GetAttribute("Release") or 0.3,
			Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = 0 })
		self.tweens[s] = down
		down:Play()
		down.Completed:Once(function(st)
			if st == Enum.PlaybackState.Completed then s:Stop() end
		end)
	end)
end

return Sfx
