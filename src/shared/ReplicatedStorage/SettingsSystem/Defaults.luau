-- PLAYER SETTINGS: the defaults and what counts as a valid value.
-- Shared by the server (saving) and the client (applying), so both always agree.
-- Change the defaults below; nothing else needs editing.
--
-- Volumes are 0..1 of the game's designed loudness:
--   1   (100%) = exactly as the sounds and music are set up in the game
--   0.5 ( 50%) = half as loud
--   0   (  0%) = silent

local Schema = {}

Schema.Defaults = {
	SfxVolume   = 1,
	MusicVolume = 1,
	Shadows     = true,
	Stopwatch   = false,   -- the run stopwatch (StarterGui.StopwatchGui's button): off until switched on
}

Schema.Keys = { "SfxVolume", "MusicVolume", "Shadows", "Stopwatch" }

local KINDS = {
	SfxVolume   = "volume",
	MusicVolume = "volume",
	Shadows     = "boolean",
	Stopwatch   = "boolean",
}

-- A valid value for `key`, or nil if the key or value is not acceptable.
-- Volumes are clamped to 0..1 and rounded to whole percent.
function Schema.Sanitize(key, value)
	local kind = KINDS[key]
	if kind == "volume" then
		if type(value) ~= "number" or value ~= value then return nil end
		local v = math.round(math.clamp(value, 0, 1) * 100) / 100
		if v == 0 then v = 0 end   -- never -0 (it would show as "-0%")
		return v
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then return nil end
		return value
	end
	return nil
end

-- A full settings table: every key present and valid, defaults for the rest.
function Schema.Normalize(t)
	local out = {}
	for _, key in ipairs(Schema.Keys) do
		local v = nil
		if type(t) == "table" then v = Schema.Sanitize(key, t[key]) end   -- (not `and/or`: false is a real value)
		if v == nil then v = Schema.Defaults[key] end
		out[key] = v
	end
	return out
end

return Schema
