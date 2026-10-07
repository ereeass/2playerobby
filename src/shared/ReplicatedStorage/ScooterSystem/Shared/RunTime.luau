-- How a course time is written, everywhere it is shown: the stopwatch
-- (StarterGui.RunTimerGui) and, later, a leaderboard. Shared so they always agree.
--   RunTime.Format(83.456)      -> "1:23.45"   (hundredths, the stopwatch)
--   RunTime.Format(83.456, 3)   -> "1:23.456"  (thousandths, a leaderboard)
--   an hour or more             -> "1:02:03.45"
-- Digits are cut, never rounded up, so a running clock never shows a time early.

local RunTime = {}

function RunTime.Format(seconds, decimals)
	decimals = decimals or 2
	seconds = math.max(0, tonumber(seconds) or 0)
	local scale = 10 ^ decimals
	local total = math.floor(seconds * scale + 1e-6)
	local frac = total % scale
	local whole = (total - frac) / scale
	local s = whole % 60
	local m = math.floor(whole / 60) % 60
	local h = math.floor(whole / 3600)
	local tail = decimals > 0 and ("." .. string.format("%0" .. decimals .. "d", frac)) or ""
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s) .. tail
	end
	return string.format("%d:%02d", m, s) .. tail
end

return RunTime
