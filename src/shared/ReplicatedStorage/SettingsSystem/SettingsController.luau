-- This player's settings (SFX volume, music volume, shadows), on THIS client only.
--
-- Started once per player by StarterPlayerScripts.SettingsClient, which loads the
-- player's saved settings from their account and applies them. Any other client
-- script (e.g. the Settings window) requires this module and gets the same controller:
--
--   local Settings = require(ReplicatedStorage.SettingsSystem.SettingsController)
--   Settings:Get("SfxVolume")                -- 0..1
--   Settings:Set("MusicVolume", 0.5)         -- applies it now (e.g. while dragging)
--   Settings:Set("MusicVolume", 0.5, true)   -- applies it now and saves it to the account
--   Settings.Changed:Connect(function(key, value) end)
--   Settings:GetSaveState()                  -- "loading" | "saving" | "saved" | "offline" | "failed"
--   Settings.SaveStateChanged:Connect(function(state) end)
--
-- HOW THE VOLUMES WORK
-- This client makes two SoundGroups, SoundService.SFX and SoundService.Music, and
-- puts every Sound it can hear into one of them as the Sound appears: the music
-- player's "BackgroundMusic" goes in Music, everything else (footsteps, UI clicks,
-- character sounds, future engine and impact sounds...) goes in SFX. A Sound can
-- choose for itself with a string attribute AudioCategory = "Music" or "SFX".
-- A Sound the game has already put in a SoundGroup of its own is left alone.
-- No Sound's own Volume is touched, so the levels the game's scripts set are kept
-- and the slider scales them: 100% = as designed.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local Lighting          = game:GetService("Lighting")

local system      = script.Parent
local Schema      = require(system:WaitForChild("Defaults"))
local remotes     = system:WaitForChild("Remotes")
local GetSettings = remotes:WaitForChild("GetSettings")
local SaveSetting = remotes:WaitForChild("SaveSetting")

local Controller = {}

local changedEvent = Instance.new("BindableEvent")
local stateEvent   = Instance.new("BindableEvent")
Controller.Changed          = changedEvent.Event
Controller.SaveStateChanged = stateEvent.Event

local values    = Schema.Normalize(nil)   -- defaults until the account's settings arrive
local saved     = {}                      -- what the account holds (or was last sent)
local touched   = {}                      -- keys the player changed before loading finished
local loaded    = false
local saveState = "loading"
local started   = false
local groups    = {}
local placeShadows = true                 -- the place's own GlobalShadows: "on" never adds more
local wroteShadows                        -- the GlobalShadows this module last wrote
local music                               -- ReplicatedStorage.Music.MusicController, if present

local function setState(state)
	if state ~= saveState then
		saveState = state
		stateEvent:Fire(state)
	end
end

---------------------------------------------------------------- applying
local function apply(key)
	local v = values[key]
	if key == "SfxVolume" then
		if groups.SFX then groups.SFX.Volume = v end
	elseif key == "MusicVolume" then
		if groups.Music then groups.Music.Volume = v end
		-- at 0% the music stops altogether (no track keeps loading in silence)
		if music then music:SetEnabled(v > 0) end
	elseif key == "Shadows" then
		wroteShadows = v and placeShadows
		Lighting.GlobalShadows = wroteShadows
	end
end

---------------------------------------------------------------- sound routing
local function groupFor(sound)
	local category = sound:GetAttribute("AudioCategory")
	if category == "Music" or (category == nil and sound.Name == "BackgroundMusic") then
		return groups.Music
	end
	return groups.SFX
end

local function route(inst)
	if not inst:IsA("Sound") then return end
	local current = inst.SoundGroup
	if current and current ~= groups.SFX and current ~= groups.Music then return end
	inst.SoundGroup = groupFor(inst)
end

local function watch(root)
	if not root then return end
	for _, d in ipairs(root:GetDescendants()) do route(d) end
	root.DescendantAdded:Connect(route)
end

local function makeGroup(name)
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = SoundService
	return g
end

---------------------------------------------------------------- api
function Controller:Start()
	assert(RunService:IsClient(), "SettingsController only runs on a player's client")
	if started then return end
	started = true

	placeShadows = Lighting.GlobalShadows
	-- If anything else changes GlobalShadows (a script, or the server), that is the
	-- game's new "on": it is remembered and the player's setting applied again on
	-- top, so "off" stays off.
	Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
		if Lighting.GlobalShadows == wroteShadows then return end
		placeShadows = Lighting.GlobalShadows
		apply("Shadows")
	end)
	pcall(function()
		local folder = ReplicatedStorage:FindFirstChild("Music")
		local module = folder and folder:FindFirstChild("MusicController")
		if module then music = require(module) end
	end)

	groups.SFX   = makeGroup("SFX")
	groups.Music = makeGroup("Music")
	for _, key in ipairs(Schema.Keys) do apply(key) end

	local player = Players.LocalPlayer
	watch(workspace)
	watch(SoundService)
	watch(player:WaitForChild("PlayerGui"))
	watch(player:WaitForChild("PlayerScripts"))

	SaveSetting.OnClientEvent:Connect(function(state)
		if state == "saved" or state == "failed" or state == "offline" then setState(state) end
	end)

	task.spawn(function()
		local ok, result = pcall(GetSettings.InvokeServer, GetSettings)
		local stored = Schema.Normalize(ok and type(result) == "table" and result.Values or nil)
		for _, key in ipairs(Schema.Keys) do
			saved[key] = stored[key]
			if not touched[key] and values[key] ~= stored[key] then
				values[key] = stored[key]
				apply(key)
				changedEvent:Fire(key, stored[key])
			end
		end
		loaded = true
		setState(ok and type(result) == "table" and result.State or "failed")
		-- anything the player changed while loading is saved now
		for key in pairs(touched) do
			if values[key] ~= saved[key] then Controller:Set(key, values[key], true) end
		end
	end)
end

function Controller:Get(key)
	return values[key]
end

function Controller:GetAll()
	return table.clone(values)
end

-- Applies `value` at once. With `save` it is also written to the player's account
-- (the server batches writes, so calling this on every slider release is fine).
function Controller:Set(key, value, save)
	local clean = Schema.Sanitize(key, value)
	if clean == nil then return end
	touched[key] = true
	if values[key] ~= clean then
		values[key] = clean
		apply(key)
		changedEvent:Fire(key, clean)
	end
	if save and loaded and saved[key] ~= clean then
		saved[key] = clean
		if saveState ~= "offline" then setState("saving") end
		SaveSetting:FireServer(key, clean)
	end
end

function Controller:GetSaveState()
	return saveState
end

return Controller
