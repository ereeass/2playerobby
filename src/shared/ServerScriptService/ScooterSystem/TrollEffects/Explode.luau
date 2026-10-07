--=====================================================================
-- Explode   (ScooterSystem.TrollEffects) - EXPLODE PLAYERS, on the server
--
-- Rocket Launch without the rocket: the scooter stops dead where it is, a short alarm builds,
-- and the same cartoon explosion goes off right there (StarterPlayerScripts.TrollFx.Explode;
-- the clock is ReplicatedStorage.TrollFx.ExplodeTimeline). Nothing is launched or moved. On
-- the server it is the shared show-and-explode troll (ScooterSystem.TrollShow), exactly as
-- Rocket Launch: only ever this one ride, then the normal death popup.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Timeline  = require(RS:WaitForChild("TrollFx"):WaitForChild("ExplodeTimeline"))
local TrollShow = require(script.Parent.Parent:WaitForChild("TrollShow"))

local Explode = {}

-- ctx: { Ride, Scooter, Life, Riders, BuyerName, Def } (TrollEffects). True once the ride is down.
function Explode.Run(ctx)
	return TrollShow.Play(ctx, "Explode", Timeline, "exploded (troll)")
end

return Explode
