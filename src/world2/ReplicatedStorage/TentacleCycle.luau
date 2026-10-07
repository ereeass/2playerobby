-- Octopus tentacles (Workspace > Octopus Tentacles, Models tagged "Tentacle"): where each one is
-- at any moment, from the shared server clock, so every screen (StarterPlayerScripts.TentacleFx)
-- and the server's hit check (ServerScriptService.TentacleSlam) agree. One cycle:
--   up     curled up in the air beside the road, swaying          (UpTime, default 1.4)
--   warn   its strip of road glows red, faster and faster, while it rears back (WarnTime, 1.3)
--   slam   smacks down across the road                          (SlamTime, 0.3)
--   down   lies on the road (harmless)                          (DownTime, 0.8)
--   rise   lifts back up                                        (RiseTime, 1.1)
-- Angle 0 = lying on the road; RaisedDeg (100) = up. Offset shifts a tentacle's cycle.
local M = {}

function M.State(t, now)
	local up   = t:GetAttribute("UpTime") or 1.4
	local warn = t:GetAttribute("WarnTime") or 1.3
	local slam = t:GetAttribute("SlamTime") or 0.3
	local down = t:GetAttribute("DownTime") or 0.8
	local rise = t:GetAttribute("RiseTime") or 1.1
	local raised = math.rad(t:GetAttribute("RaisedDeg") or 100)
	local rear = raised + math.rad(22)
	local x = (now - (t:GetAttribute("Offset") or 0)) % (up + warn + slam + down + rise)
	local sway = math.rad(4) * math.sin(now * 2.1 + (t:GetAttribute("Offset") or 0))
	if x < up then return raised + sway, "up", 0 end
	x -= up
	if x < warn then local k = x / warn return raised + (rear - raised) * math.sin(k * math.pi / 2) + sway * (1 - k), "warn", k end
	x -= warn
	if x < slam then local k = x / slam return rear * (1 - k * k), "slam", k end
	x -= slam
	if x < down then return 0, "down", x / down end
	x -= down
	local k = x / rise
	return raised * (0.5 - 0.5 * math.cos(k * math.pi)), "rise", k
end

return M
