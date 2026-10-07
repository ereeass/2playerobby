--=====================================================================
-- DuoState   (ScooterSystem, server)
--
-- What a ride is right now, as the Troll window sees it - one rule, used by the spectate list
-- (ScooterSystem.Spectate) and the Troll effects (ScooterSystem.TrollEffects). It only reads
-- RideManager's rides; it never changes one.
--
--   Watchable(ride)  its duo can be watched: live (not ended, not down, not being revived),
--                    BOTH riders in the game and still held on the scooter - or a troll's show
--                    is playing on it (ride.TrollShow), until that show is over
--   Trollable(ride)  a troll may be bought onto it now: watchable, and nothing has it already
--                    (another troll, an obstacle that has claimed it, the moments after a revive)
--=====================================================================

local RideManager = require(script.Parent:WaitForChild("RideManager"))

local DuoState = {}

local function held(h)
	return h ~= nil and not h.Released
end

function DuoState.Watchable(ride)
	if not ride or ride._ended then return false end
	local scooter = ride.Scooter
	if not (scooter and scooter.Parent and scooter.PrimaryPart) then return false end
	if ride.TrollShow then return true end   -- a troll is playing on it: watched to the end
	if ride.Down then return false end
	local d, p = ride.Driver, ride.Passenger
	if not (d and p and d.Parent and p.Parent) then return false end
	if RideManager.IsReviving(d) or RideManager.IsReviving(p) then return false end
	return held(ride.Riders.Driver) and held(ride.Riders.Passenger)
end

function DuoState.Trollable(ride)
	if not DuoState.Watchable(ride) then return false end
	if ride.TrollShow or ride.Troll or ride.Down or ride.Doomed then return false end
	if ride.GraceUntil and os.clock() < ride.GraceUntil then return false end   -- just revived
	return true
end

return DuoState
