-- Heart hammers (Workspace > Heart Hammers, Models tagged "HeartHammer"): the hammer's angle at
-- any moment, from the shared server clock, so every screen (StarterPlayerScripts.HammerSlamFx)
-- and the server's kill check (ServerScriptService.HammerSlam) agree on it.
-- 0 = slammed flat on the road; RestDeg = held up (the angle it's built at in Studio).
-- One cycle: held up, winding back a little at the end (UpTime) -> slams (SlamTime) -> rests on
-- the road (DownTime) -> lifts back up (RiseTime). Per-hammer attributes on the Model:
--   Offset [0]  UpTime [1.3]  SlamTime [0.28]  DownTime [0.7]  RiseTime [1.1]  RestDeg [100]

local M = {}
local WIND, WIND_DEG = 0.3, 15

-- (angle in radians, phase, 0-1 progress through that phase) for `hammer` at server time `now`
function M.State(hammer, now)
	local rest = math.rad(hammer:GetAttribute("RestDeg") or 100)
	local u = hammer:GetAttribute("UpTime") or 1.3
	local s = hammer:GetAttribute("SlamTime") or 0.28
	local d = hammer:GetAttribute("DownTime") or 0.7
	local r = hammer:GetAttribute("RiseTime") or 1.1
	local wind = math.rad(WIND_DEG)
	local t = (now - (hammer:GetAttribute("Offset") or 0)) % (u + s + d + r)
	if t < u then
		local w = math.clamp((t - (u - WIND)) / WIND, 0, 1)
		return rest + wind * math.sin(w * math.pi / 2), "up", t / u
	end
	t -= u
	if t < s then local k = t / s return (rest + wind) * (1 - k * k), "slam", k end
	t -= s
	if t < d then return 0, "down", t / d end
	t -= d
	local k = t / r
	return rest * (0.5 - 0.5 * math.cos(k * math.pi)), "rise", k
end

return M
