-- Which side of a capsule booth a point is on. Shared so the server's entry check
-- (CapsuleEntry.CanEnterFrom) and each client's prompt visibility (CapsuleFx)
-- always agree.
--
-- Booth space comes from the booth model's pivot: its LookVector points OUT through
-- the glass door, and the door frame's outer face is 2.75 studs in front of it.

local BoothEntrance = {}

-- Just past the door frame. From anywhere this far forward, the walk to the doorway
-- can never cut through the booth.
BoothEntrance.FrontMin = 2.9

-- forward (out through the glass), right, up
function BoothEntrance.Local(booth, pos)
	local l = booth.WorldPivot:PointToObjectSpace(pos)
	return -l.Z, l.X, l.Y
end

-- `slack` lets the server accept a press made right on the line a moment ago
function BoothEntrance.IsInFront(booth, pos, slack)
	local forward = BoothEntrance.Local(booth, pos)
	return forward >= BoothEntrance.FrontMin - (slack or 0)
end

return BoothEntrance
