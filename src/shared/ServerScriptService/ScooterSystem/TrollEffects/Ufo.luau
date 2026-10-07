--=====================================================================
-- Ufo   (ScooterSystem.TrollEffects) - UFO ABDUCTION, on the server
--
-- A UFO swoops in over the scooter, beams it and both riders up and flies off with them
-- (StarterPlayerScripts.TrollFx.Ufo; the clock is ReplicatedStorage.TrollFx.UfoTimeline).
-- On the server it is the shared show troll (ScooterSystem.TrollShow), exactly as Explode and
-- Freeze Players: only ever this one ride, then the normal death popup.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Timeline  = require(RS:WaitForChild("TrollFx"):WaitForChild("UfoTimeline"))
local TrollShow = require(script.Parent.Parent:WaitForChild("TrollShow"))

local Ufo = {}

-- ctx: { Ride, Scooter, Life, Riders, BuyerName, Def } (TrollEffects). True once the ride is down.
function Ufo.Run(ctx)
	return TrollShow.Play(ctx, "Ufo", Timeline, "abducted (troll)")
end

return Ufo
