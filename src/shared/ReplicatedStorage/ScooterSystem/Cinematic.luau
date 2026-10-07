--=====================================================================
-- Cinematic   (ScooterSystem, on each player's machine)
--
-- "A cutscene has this player right now" - the finish-line victory cinematic
-- (StarterPlayerScripts.FinishCutscene) holds it while it plays. While it is held the
-- ride's own controls stand down, whatever keys or pedals are held:
--   RideGui.Controller  steers straight (Driver) and brakes the motor to a stop and
--                       holds it there (Passenger), without the screech; the horn and
--                       any touch pedal let go, H does nothing, and the character's own
--                       controls stay off. When it ends, the keys really held count again.
--   ScooterFx           leaves the camera's field of view to the cutscene.
-- It never talks to the server itself: the brake reaches the scooter through the ride's
-- normal input (Remotes.DriveInput), and nobody else's game changes.
--
--   Cinematic.Begin(key) / Cinematic.End(key)   hold it / let go (holders may overlap)
--   Cinematic.IsActive()                         anyone holding it
--   Cinematic.Changed                            (active) whenever that flips
--=====================================================================

local Cinematic = {}

local holders = {}
local changed = Instance.new("BindableEvent")
Cinematic.Changed = changed.Event

function Cinematic.IsActive()
	return next(holders) ~= nil
end

function Cinematic.Begin(key)
	if holders[key] then return end
	local was = Cinematic.IsActive()
	holders[key] = true
	if not was then changed:Fire(true) end
end

function Cinematic.End(key)
	if not holders[key] then return end
	holders[key] = nil
	if not Cinematic.IsActive() then changed:Fire(false) end
end

return Cinematic
