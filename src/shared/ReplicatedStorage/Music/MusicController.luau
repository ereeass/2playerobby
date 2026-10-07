-- Background music, played on THIS client only.
--
-- Every player runs their own copy: their own shuffled order, their own Sound and
-- their own on/off switch. Nothing here talks to the server or to other players,
-- so one player's music can never change anyone else's.
--
-- Started once per player by StarterPlayerScripts.MusicClient. Any other client
-- script (e.g. a Settings menu) requires this module and gets the same controller:
--
--   local Music = require(ReplicatedStorage.Music.MusicController)
--   Music:SetEnabled(false)    -- stop the music and keep it off
--   Music:SetEnabled(true)     -- carry on where it stopped
--   Music:Toggle()             -- flip it; returns the new state
--   Music:IsEnabled()          -- true / false
--   Music:GetCurrentTrack()    -- { Name = "Track 4", Id = 92611825652967 } or nil
--   Music.Changed:Connect(function(enabled, track) end)   -- on/off or track changed
--   Music:SetSuspended(true)   -- pause the playlist for something else (area music) without
--                              -- touching the player's own on/off; false carries on
--
-- SetEnabled may be called before Start (e.g. to apply a saved setting).

local ContentProvider = game:GetService("ContentProvider")
local RunService      = game:GetService("RunService")
local SoundService    = game:GetService("SoundService")

local Tracks = require(script.Parent:WaitForChild("Tracks"))

local VOLUME       = 0.125  -- sits under the game's own sound effects (0.35 minus 40%)
local MIN_LENGTH   = 1      -- seconds; anything shorter is not a real track
local LOAD_TIMEOUT = 15     -- seconds to wait for a track before skipping it
local RETRY_DELAY  = 30     -- pause after every track failed in a row (e.g. offline)

local MusicController = {}

local changedEvent = Instance.new("BindableEvent")
MusicController.Changed = changedEvent.Event

local enabled, started = true, false
local suspended = false     -- paused for area music (StarterPlayerScripts.AreaMusic)
local sound                 -- the ONE Sound this player's music ever uses
local current               -- the track in that Sound (loading or playing)
local order, pos = {}, 0
local lastPlayedId
local run = 0               -- bumped to cancel a track that is still loading
local warned = {}           -- a broken track is reported once, not every round
local rng = Random.new()    -- seeded per client: every player gets their own order

local function copy(track)
	return track and { Name = track.Name, Id = track.Id } or nil
end
local function changed()
	changedEvent:Fire(enabled, copy(current))
end
local function idOf(track)
	return "rbxassetid://" .. tostring(track.Id)
end

---------------------------------------------------------------- playlist
-- A fresh random order of every track. A new round never opens with the track
-- that has just finished.
local function reshuffle()
	order = table.clone(Tracks)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	if #order > 1 and order[1].Id == lastPlayedId then
		local j = rng:NextInteger(2, #order)
		order[1], order[j] = order[j], order[1]
	end
	pos = 0
end

local function nextTrack()
	pos += 1
	if pos > #order then
		reshuffle()
		pos = 1
	end
	return order[pos]
end

---------------------------------------------------------------- playback
-- Waits for the Sound's track to load: "ok", "failed" (e.g. the asset is not
-- approved for this game), "timeout", or "cancelled" once `id` is out of date.
local function waitForLoad(id)
	if sound.IsLoaded then return "ok" end
	local result
	local conn = sound.Loaded:Connect(function() result = result or "ok" end)
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound }, function(_, status)
				if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
					result = result or "failed"
				end
			end)
		end)
		if not ok then result = result or "failed" end
	end)
	local t0 = os.clock()
	while not result and run == id and os.clock() - t0 < LOAD_TIMEOUT do
		if sound.IsLoaded then result = "ok" end
		task.wait(0.1)
	end
	conn:Disconnect()
	if run ~= id then return "cancelled" end
	return result or "timeout"
end

-- Plays the next track that works, skipping any that will not load or are too
-- short, so one broken asset never stops the playlist. `first` plays that track
-- instead of moving on (used when music is switched back on mid-load).
local function playFrom(id, first)
	local failedInARow = 0
	while run == id and enabled and not suspended do
		local track = first or nextTrack()
		first = nil
		current = track
		sound:Stop()
		sound.SoundId = idOf(track)
		sound.TimePosition = 0

		local result = waitForLoad(id)
		if result == "cancelled" or run ~= id or not enabled or suspended then return end
		if result == "ok" and sound.TimeLength >= MIN_LENGTH then
			lastPlayedId = track.Id
			sound:Play()
			changed()
			return
		end

		if not warned[track.Id] then
			warned[track.Id] = true
			print(("[Music] skipping %s (%s): %s"):format(track.Name, tostring(track.Id),
				result == "ok" and "too short" or result))
		end
		failedInARow += 1
		if failedInARow >= #Tracks then
			-- nothing will load right now: wait a while, then try the playlist again
			failedInARow = 0
			local t0 = os.clock()
			while run == id and enabled and not suspended and os.clock() - t0 < RETRY_DELAY do task.wait(1) end
		end
	end
end

local function startNext(first)
	run += 1
	task.spawn(playFrom, run, first)
end

-- Music switched back on: finish the track that was paused, or restart the one
-- that never got going, or move on.
local function resume()
	local loaded = current and sound.IsLoaded and sound.SoundId == idOf(current)
	if loaded and sound.TimePosition > 0 and sound.TimePosition < sound.TimeLength - 0.5 then
		run += 1
		sound:Resume()
	elseif current and sound.TimePosition <= 0 then
		startNext(current)
	else
		startNext()
	end
end

---------------------------------------------------------------- api
function MusicController:Start()
	assert(RunService:IsClient(), "MusicController only runs on a player's client")
	if started then return end
	started = true

	-- In SoundService on this client: it exists for this player alone, and it is
	-- not part of the character, so dying or respawning never touches it.
	sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.Volume = VOLUME
	sound.Looped = false
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		if enabled and not suspended then startNext() end
	end)

	reshuffle()
	if enabled and not suspended then startNext() end
end

function MusicController:SetEnabled(on)
	on = on and true or false
	if on == enabled then return end
	enabled = on
	if started and not suspended then
		if on then
			resume()
		else
			run += 1        -- cancel a track that is still loading
			sound:Pause()
		end
	end
	changed()
end

function MusicController:SetSuspended(on)
	on = on and true or false
	if on == suspended then return end
	suspended = on
	if not started or not enabled then return end
	if on then
		run += 1        -- cancel a track that is still loading
		sound:Pause()
	else
		resume()
	end
end

function MusicController:IsSuspended()
	return suspended
end

function MusicController:IsEnabled()
	return enabled
end

function MusicController:Toggle()
	self:SetEnabled(not enabled)
	return enabled
end

function MusicController:GetCurrentTrack()
	return copy(current)
end

return MusicController
