--=====================================================================
-- Freeze   (ScooterSystem.TrollEffects) - FREEZE PLAYERS, on the server
--
-- Explode Players with ice instead of a bomb: the scooter stops dead where it is, a block of
-- ice grows round it and both riders, holds them, cracks and shatters
-- (StarterPlayerScripts.TrollFx.Freeze; the clock is ReplicatedStorage.TrollFx.FreezeTimeline).
-- On the server it is the shared show-and-explode troll (ScooterSystem.TrollShow), exactly as
-- Explode Players: only ever this one ride, then the normal death popup.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Timeline  = require(RS:WaitForChild("TrollFx"):WaitForChild("FreezeTimeline"))
local TrollShow = require(script.Parent.Parent:WaitForChild("TrollShow"))

local Freeze = {}

-- ctx: { Ride, Scooter, Life, Riders, BuyerName, Def } (TrollEffects). True once the ride is down.
function Freeze.Run(ctx)
	return TrollShow.Play(ctx, "Freeze", Timeline, "frozen (troll)")
end

return Freeze
