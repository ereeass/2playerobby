-- Area music, on THIS player's machine only. Settings: ReplicatedStorage.Music.AreaMusic
-- (Enabled = false turns it all off and leaves the lobby playlist exactly as before).
--
-- The server says which area this player is in (Remotes.AreaChanged: the checkpoint their
-- ride started from, then each new checkpoint the pair reaches). While riding, that area's
-- track plays, looped and quiet, and the lobby playlist is paused (MusicController:SetSuspended,
-- which never touches the player's own music on/off). When the ride ends the area track fades
-- out and the playlist carries on. Music Volume at 0% (music off) silences this too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")

local Settings = require(ReplicatedStorage:WaitForChild("Music"):WaitForChild("AreaMusic"))
if not Settings.Enabled then return end

local Music   = require(ReplicatedStorage.Music:WaitForChild("MusicController"))
local Remotes = ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Remotes")

local riding, area = false, nil
local playingId = nil
local sound = Instance.new("Sound")
sound.Name = "AreaMusic"
sound:SetAttribute("AudioCategory", "Music")      -- goes in the Music group: Music Volume applies
sound.Looped = true
sound.Volume = 0
sound.Parent = SoundService

local fadeTween
local function fadeTo(vol, done, time)
	if fadeTween then fadeTween:Cancel() end
	fadeTween = TweenService:Create(sound, TweenInfo.new(time or Settings.Fade or 2, Enum.EasingStyle.Sine), { Volume = vol })
	if done then fadeTween.Completed:Once(function(state) if state == Enum.PlaybackState.Completed then done() end end) end
	fadeTween:Play()
end

local token = 0
local function update()
	token += 1
	local my = token
	local track = riding and area and Settings.Tracks[area]
	if track and Music:IsEnabled() then
		Music:SetSuspended(true)
		if playingId ~= track.Id then
			playingId = track.Id
			-- fade the old one out (if any), then the new one in
			local fromLobby = not (sound.IsPlaying and sound.Volume > 0.01)
			local function start()
				if token ~= my then return end
				sound:Stop()
				sound.SoundId = "rbxassetid://" .. track.Id
				-- play and loop only the part of the file with music in it
				local a, b = track.Start or 0, track.End or 1e6
				sound.PlaybackRegionsEnabled = true
				sound.PlaybackRegion = NumberRange.new(a, b)
				sound.LoopRegion = NumberRange.new(a, b)
				sound.TimePosition = a
				sound:Play()
				fadeTo(Settings.Volume or 0.12, nil, fromLobby and (Settings.FadeIn or 0.4) or nil)
			end
			if fromLobby then start() else fadeTo(0, start) end
		elseif not sound.IsPlaying then
			sound:Play(); fadeTo(Settings.Volume or 0.12, nil, Settings.FadeIn or 0.4)
		end
	else
		playingId = nil
		if sound.IsPlaying then
			fadeTo(0, function() if token == my then sound:Stop() end end)
		end
		-- back to the lobby playlist once the area track has had a moment to fade
		task.delay(riding and 0 or 0.6, function() if token == my then Music:SetSuspended(false) end end)
	end
end

Remotes:WaitForChild("AreaChanged").OnClientEvent:Connect(function(order)
	if type(order) ~= "number" then return end
	riding, area = true, order
	update()
end)
Remotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(state)
	local now = type(state) == "table" and state.Phase == "Riding"
	if now == riding then return end
	riding = now
	if not riding then area = nil end
	update()
end)
Music.Changed:Connect(function() update() end)
