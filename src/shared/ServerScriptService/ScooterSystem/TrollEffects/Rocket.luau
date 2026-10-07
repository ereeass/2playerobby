--=====================================================================
-- Rocket   (ScooterSystem.TrollEffects) - ROCKET LAUNCH, on the server
--
-- The show plays on every machine (StarterPlayerScripts.TrollFx.Rocket: a rocket booster pops
-- out from under the scooter, it climbs straight up 100 studs and explodes; the clock is
-- ReplicatedStorage.TrollFx.RocketTimeline). On the server it is the shared show-and-explode
-- troll (ScooterSystem.TrollShow: freeze, the riders told, gone at the explosion, the death
-- popup at the end - only ever this one ride).
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Timeline  = require(RS:WaitForChild("TrollFx"):WaitForChild("RocketTimeline"))
local TrollShow = require(script.Parent.Parent:WaitForChild("TrollShow"))

local Rocket = {}

-- ctx: { Ride, Scooter, Life, Riders, BuyerName, Def } (TrollEffects). True once the ride is down.
function Rocket.Run(ctx)
	return TrollShow.Play(ctx, "Rocket", Timeline, "rocket launched (troll)")
end

return Rocket
