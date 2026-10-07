--=====================================================================
-- FinishCutscene / FinishLine
--
-- Where the finish lines are, and whether this player's scooter just crossed one.
--   Gates   every part tagged Config.FinishTag (the course's is Workspace["Finish
--           Area"].FinishGate.Gate, in a Persistent model so every machine always has
--           it). A gate's LookVector points across it; Size.X is how wide the line is and
--           Size.Y how high it counts.
--   Record  while the scooter is near a gate, where it has been: a point every
--           RECORD_STEP studs, the last RECORD_LENGTH studs of them, so the cinematic
--           can replay the actual road in, whichever way it bends.
--   Cross   the chassis going from a gate's back to its front, between its ends and
--           within its height, in one frame's move (a teleport or a respawn never
--           counts). Reported with the gate, the crossing point and the recording.
--=====================================================================

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent:WaitForChild("Config"))

local FinishLine = {}

local RECORD_RANGE  = 150   -- studs from a gate's edge where recording starts
local RECORD_LENGTH = 60    -- studs of road kept
local RECORD_STEP   = 0.5   -- studs between recorded points
local MAX_JUMP      = 25    -- studs in one frame: more is a teleport, never a crossing

local gates = {}
local function track(p)
	if p:IsA("BasePart") then gates[p] = true end
end
for _, p in ipairs(CollectionService:GetTagged(Config.FinishTag)) do track(p) end
CollectionService:GetInstanceAddedSignal(Config.FinishTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(Config.FinishTag):Connect(function(p) gates[p] = nil end)

local samples, length = {}, 0   -- the recording, oldest first: { pos = Vector3, cf = CFrame }
local chassisNow, lastPos

local function forget()
	table.clear(samples)
	length = 0
end

local function nearAGate(pos)
	for g in pairs(gates) do
		if g.Parent and (g.Position - pos).Magnitude < RECORD_RANGE + g.Size.X / 2 then return true end
	end
	return false
end

-- Every frame, with this player's chassis (nil while they aren't riding). A crossing
-- (see the end of this function), or nil.
function FinishLine.Step(chassis)
	if chassis ~= chassisNow then
		chassisNow, lastPos = chassis, nil
		forget()
	end
	if not (chassis and chassis.Parent) then return nil end
	local pos = chassis.Position
	local prev = lastPos
	lastPos = pos
	if not nearAGate(pos) then
		if #samples > 0 then forget() end
		return nil
	end

	local last = samples[#samples]
	if not last or (pos - last.pos).Magnitude >= RECORD_STEP then
		if last then length += (pos - last.pos).Magnitude end
		table.insert(samples, { pos = pos, cf = chassis.CFrame })
		while #samples > 2 and length - (samples[2].pos - samples[1].pos).Magnitude >= RECORD_LENGTH do
			length -= (samples[2].pos - samples[1].pos).Magnitude
			table.remove(samples, 1)
		end
	end

	if not prev or (pos - prev).Magnitude > MAX_JUMP then return nil end
	for gate in pairs(gates) do
		if gate.Parent then
			local cf, size = gate.CFrame, gate.Size
			local a, b = cf:PointToObjectSpace(prev), cf:PointToObjectSpace(pos)
			-- +Z is the gate's back: the side riders come from
			if a.Z > 0 and b.Z <= 0 then
				local k = a.Z / (a.Z - b.Z)
				local at = a:Lerp(b, k)
				if math.abs(at.X) <= size.X / 2 and math.abs(at.Y) <= size.Y / 2 then
					local point = prev:Lerp(pos, k)
					local approach = {}
					for _, s in ipairs(samples) do
						if cf:PointToObjectSpace(s.pos).Z > 0.05 then table.insert(approach, s) end
					end
					table.insert(approach, { pos = point, cf = chassis.CFrame.Rotation + point })
					return {
						Gate = gate, GateCF = cf, GateSize = size,
						Point = point,         -- where the chassis crossed
						Lateral = at.X,        -- how far off the gate's middle (+ = its right)
						Approach = approach,   -- the road in, oldest first, ending on the line
						Chassis = chassis,
					}
				end
			end
		end
	end
	return nil
end

return FinishLine
