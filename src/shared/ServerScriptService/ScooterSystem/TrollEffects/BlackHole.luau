--=====================================================================
-- BlackHole   (ScooterSystem.TrollEffects) - BLACK HOLE, on the server
--
-- A black hole tears open ahead of the duo, builds, and drags the scooter and both riders in
-- (StarterPlayerScripts.TrollFx.BlackHole; the clock is ReplicatedStorage.TrollFx.
-- BlackHoleTimeline). On the server it is the shared show troll (ScooterSystem.TrollShow),
-- exactly as the others: only ever this one ride - its scooter held still, its two riders told -
-- then the normal death popup. There is no force, gravity or area anywhere: the pull is only a
-- picture, drawn on each screen, of this one scooter. Nobody else can ever be touched by it.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Timeline  = require(RS:WaitForChild("TrollFx"):WaitForChild("BlackHoleTimeline"))
local TrollShow = require(script.Parent.Parent:WaitForChild("TrollShow"))

local BlackHole = {}

-- ctx: { Ride, Scooter, Life, Riders, BuyerName, Def } (TrollEffects). True once the ride is down.
function BlackHole.Run(ctx)
	return TrollShow.Play(ctx, "BlackHole", Timeline, "sucked into a black hole (troll)")
end

return BlackHole
