-- Volcano (Workspace > Volcano, tagged "Volcano"): where its eruption is at any moment, from the
-- shared server clock, so every screen (StarterPlayerScripts.VolcanoFx) and the server's kill
-- check (ServerScriptService.VolcanoLava) agree. One cycle of CycleTime seconds (default 7):
--   0.0 - 1.2  erupts: a lava fountain out of the crater
--   0.6 - 2.0  the lava runs down the side and the chute to the road
--   2.0 - 2.6  it spreads over the road (deadly where it has reached)
--   2.6 - 4.6  it sits on the road (deadly)
--   4.6 - 5.1  it fades away (safe)
--   then calm until the next eruption
-- Attributes on the Model: CycleTime [7], Offset [0] (seconds, to shift it).

local M = {}

local function k(t, a, b) return math.clamp((t - a) / (b - a), 0, 1) end

function M.State(volcano, now)
	local cycle = volcano:GetAttribute("CycleTime") or 7
	local t = (now - (volcano:GetAttribute("Offset") or 0)) % cycle
	local s = {}
	s.fountain = (t < 1.2) and math.sin(t / 1.2 * math.pi) or 0     -- 0..1..0
	s.erupting = t < 1.0
	s.flow     = (t < 4.6) and k(t, 0.6, 2.0) or 1                  -- how far down the lava is
	s.spread   = (t < 4.6) and k(t, 2.0, 2.6) or 1                  -- how much of the road it covers
	s.fade     = (t < 4.6) and 0 or k(t, 4.6, 5.1)                  -- 0 = solid, 1 = gone
	if t >= 5.1 then s.flow, s.spread, s.fade = 0, 0, 1 end
	s.deadly   = t >= 2.0 and t < 4.6
	s.warn     = (t < 2.0) and k(t, 0.1, 2.0) or 0                   -- red warning growing to where the lava will land
	return s
end

return M
