-- Stomp bears (Workspace > Stomp Bears, Models tagged "StompBear"): where a bear is at any moment,
-- worked out from the shared server clock, so every screen (StarterPlayerScripts.BearStompFx)
-- and the server's kill check (ServerScriptService.BearStomp) agree on it.
-- One cycle: sits on the road (GroundTime) -> rises (RiseTime) -> hovers, bobbing (AirTime)
-- -> slams down (DropTime). Per-bear attributes on the Model (defaults in brackets):
--   Offset [0]  GroundTime [1.2]  RiseTime [0.9]  AirTime [2]  DropTime [0.35]  Height [14]

local M = {}

-- (height above its resting spot, phase, 0-1 progress through that phase) for `bear` at server time `now`
function M.State(bear, now)
	local g = bear:GetAttribute("GroundTime") or 1.2
	local r = bear:GetAttribute("RiseTime") or 0.9
	local a = bear:GetAttribute("AirTime") or 2
	local d = bear:GetAttribute("DropTime") or 0.35
	local h = bear:GetAttribute("Height") or 14
	local t = (now - (bear:GetAttribute("Offset") or 0)) % (g + r + a + d)
	if t < g then return 0, "ground", t / g end
	t -= g
	if t < r then local k = t / r return h * (1 - (1 - k) ^ 2), "rise", k end
	t -= r
	if t < a then return h + 0.6 * math.sin(t / a * math.pi * 2), "air", t / a end
	t -= a
	local k = t / d
	return h * (1 - k * k), "drop", k
end

return M
