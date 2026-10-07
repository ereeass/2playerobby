--=====================================================================
-- Slap   (ScooterSystem.TrollEffects) - GIANT SLAP, on the server
--
-- A giant cartoon glove on a stick swoops down beside the duo, hangs there awkwardly, then
-- SLAPS them off into the distance (StarterPlayerScripts.TrollFx.Slap; the clock is
-- ReplicatedStorage.TrollFx.SlapTimeline). On the server it is the shared show troll
-- (ScooterSystem.TrollShow), exactly as the others: only ever this one ride, then the normal
-- death popup.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Timeline  = require(RS:WaitForChild("TrollFx"):WaitForChild("SlapTimeline"))
local TrollShow = require(script.Parent.Parent:WaitForChild("TrollShow"))

local Slap = {}

-- ctx: { Ride, Scooter, Life, Riders, BuyerName, Def } (TrollEffects). True once the ride is down.
function Slap.Run(ctx)
	return TrollShow.Play(ctx, "Slap", Timeline, "slapped (troll)")
end

return Slap
