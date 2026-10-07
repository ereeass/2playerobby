-- Glass-door entry for the capsule booths.
--
-- The server only decides WHEN a booth's door is open and whether its bottom
-- lights show "occupied" (attributes on the booth model); every client animates
-- the door and lights itself (StarterPlayerScripts.CapsuleFx) so the motion is
-- smooth for everyone. Characters are simulated by their own client, so the door
-- a player sees is the one their character collides with.
--
-- A booth without a Door (e.g. the original capsules restored) keeps the old
-- instant placement.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local BoothEntrance = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("BoothEntrance"))
local CollectionService = game:GetService("CollectionService")
local ReturnHome = RS.ScooterSystem:WaitForChild("Remotes"):WaitForChild("ReturnHome")

local CapsuleEntry = {}

local OPEN_LEAD    = 0.12   -- let the glass start rising before the walk begins
local STEP_TIMEOUT = 1.8    -- per waypoint
local STUCK_TIME   = 0.45   -- no progress for this long = blocked, place them instead
local CLOSE_DELAY  = 0.15   -- after the player is through the doorway
local SETTLE_TIME  = 0.45   -- client close tween (0.3 s) + margin before the tidy-up

local tokens = {}           -- [booth] = n; only the newest walk-in may close its door
local walking = {}          -- [player] = { t }: a walk-in of theirs is still under way

-- Every character move here is made on the player's own machine too (Remotes.ReturnHome):
-- it simulates the character, and a move made only by the server can be undone by the old
-- position still in flight from there.
local function moveCharacter(player, ch, cf)
	ch:PivotTo(cf)
	local root = ch:FindFirstChild("HumanoidRootPart")
	if root then root.AssemblyLinearVelocity = Vector3.zero end
	if player and player.Parent then ReturnHome:FireClient(player, cf) end
end
local slotLookup = function() return nil end

-- TeamManager tells us who is queued, so strangers can be moved out of a booth.
function CapsuleEntry.SetSlotLookup(fn)
	slotLookup = fn
end

local function boothOf(part)
	local ref = part:FindFirstChild("CapsuleModel")
	local m = ref and ref.Value
	if m and m:FindFirstChild("Door") then return m end
	return nil
end

-- `player`: who is in it (on only). Their UserId goes on the booth as OccupantId, set
-- before Occupied, so every client can show their picture with the green glow (CapsuleFx).
function CapsuleEntry.SetOccupied(part, on, player)
	local m = boothOf(part)
	if not m then return end
	if on then
		local id = typeof(player) == "Instance" and player.UserId or 0
		if m:GetAttribute("OccupantId") ~= id then m:SetAttribute("OccupantId", id) end
	end
	if m:GetAttribute("Occupied") ~= on then m:SetAttribute("Occupied", on) end
	if not on and (m:GetAttribute("OccupantId") or 0) ~= 0 then m:SetAttribute("OccupantId", 0) end
end

-- Booth space: X = right, Y = up from the floor, -Z = out through the glass.
local function forwardOf(booth, pos)
	local l = booth.WorldPivot:PointToObjectSpace(pos)
	return -l.Z, l.X, l.Y
end

-- `limit` is how far toward the glass still counts (its inner face is at 2.45)
local function isInside(booth, pos, limit)
	local f, r, u = forwardOf(booth, pos)
	return f < limit and f > -2 and math.abs(r) < 2.05 and u > -1 and u < 7
end

-- inside, or caught in the door frame (its outer face is at 2.75)
local function inDoorway(booth, pos)
	local f, r, u = forwardOf(booth, pos)
	return f < 2.9 and f > -2 and math.abs(r) < 2.2 and u > -1 and u < 7
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local FRONT_SLACK = 0.4     -- the client hides the prompt at FrontMin; allow for lag
local RANGE_SLACK = 6       -- studs past the prompt's reach, for lag and big avatars

-- The glass door is the only way in. The prompt reaches through the walls, and
-- from the back or the sides the walk-in path runs into the booth and falls back to
-- placing the player inside - through the wall, glass opening and all. So an entry
-- only counts from in front of the door, within the prompt's reach (which also
-- covers a request that did not come from the prompt).
function CapsuleEntry.CanEnterFrom(part, pos)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt and (pos - part.Position).Magnitude > prompt.MaxActivationDistance + RANGE_SLACK then
		return false
	end
	local booth = boothOf(part)
	if not booth then return true end   -- a booth without a door (originals) has no front
	return BoothEntrance.IsInFront(booth, pos, FRONT_SLACK)
end

-- `onArrived` (optional) runs once the player is in the booth, turned to face out
-- (at once for a booth without a door). It does not run if the walk-in was
-- called off (stillValid false: they left, died or were moved on).
function CapsuleEntry.WalkIn(player, part, standCF, stillValid, onArrived)
	local ch    = player.Character
	local hum   = ch and ch:FindFirstChildOfClass("Humanoid")
	local root  = ch and ch:FindFirstChild("HumanoidRootPart")
	local booth = boothOf(part)
	if not (booth and hum and root) then
		if ch then moveCharacter(player, ch, standCF) end
		if onArrived then task.spawn(onArrived) end
		return
	end

	tokens[booth] = (tokens[booth] or 0) + 1
	local token = tokens[booth]
	local pivot = booth.WorldPivot
	local fwd = pivot.LookVector
	local facing = CFrame.lookAt(standCF.Position, standCF.Position + fwd)   -- face out through the glass

	local function valid()
		return stillValid() and ch.Parent ~= nil and root.Parent ~= nil and hum.Health > 0
	end
	local function closeDoor()
		if tokens[booth] == token then booth:SetAttribute("DoorOpen", false) end
	end
	local closing = false
	local function markInside()
		if closing then return end
		closing = true
		if valid() then CapsuleEntry.SetOccupied(part, true, player) end
		task.delay(CLOSE_DELAY, closeDoor)
	end

	booth:SetAttribute("DoorOpen", true)
	local walk = { t = os.clock() }
	walking[player] = walk
	local function walkDone() if walking[player] == walk then walking[player] = nil end end

	task.spawn(function()
		task.wait(OPEN_LEAD)

		-- line up in front of the doorway (unless already there), walk to the back,
		-- then step forward so they turn round and face out. Targets overshoot and
		-- the reach radii are generous: Humanoid:MoveTo ignores very short steps
		-- and big avatars touch the back wall early.
		local waypoints = {}
		local f, r = forwardOf(booth, root.Position)
		if not (f > 2.9 and math.abs(r) < 1.4) then
			table.insert(waypoints, { pivot:PointToWorldSpace(Vector3.new(0, 0, -4.8)), 1.5 })
		end
		table.insert(waypoints, { pivot:PointToWorldSpace(Vector3.new(0, 0, 1.0)), 1.0 })
		table.insert(waypoints, { pivot:PointToWorldSpace(Vector3.new(0, 0, -1.3)), 0.9 })

		local outcome = "walked"
		for _, wp in ipairs(waypoints) do
			local target, reach = wp[1], wp[2]
			hum:MoveTo(target)
			local t0 = os.clock()
			local best, bestAt = math.huge, t0
			while true do
				RunService.Heartbeat:Wait()
				if not valid() then outcome = "cancelled"; break end
				if isInside(booth, root.Position, 1.2) then markInside() end
				local d = (flat(root.Position) - flat(target)).Magnitude
				if d < reach then break end
				local now = os.clock()
				if d < best - 0.05 then best, bestAt = d, now end
				if now - bestAt > STUCK_TIME or now - t0 > STEP_TIMEOUT then outcome = "blocked"; break end
			end
			if outcome ~= "walked" then break end
		end

		-- the old placement, used only when the way in is blocked
		if outcome == "blocked" and valid() and not isInside(booth, root.Position, 2.2) then
			moveCharacter(player, ch, facing)
		elseif outcome ~= "cancelled" and valid() and root.CFrame.LookVector:Dot(fwd) < 0.3 then
			-- big avatars have no room to turn round by walking: turn them once, in place
			moveCharacter(player, ch, CFrame.lookAt(root.Position, root.Position + fwd))
		end
		-- never leave a walk target behind (it would pull them back here later)
		if ch.Parent and root.Parent then hum:MoveTo(root.Position) end
		if outcome ~= "cancelled" and valid() then
			markInside()
			if onArrived then task.spawn(onArrived) end
		end
		if not closing then closeDoor() end

		-- once the glass is down: the occupant must be inside, strangers must not be
		task.wait(CLOSE_DELAY + SETTLE_TIME)
		walkDone()
		if tokens[booth] ~= token then return end
		if valid() and not isInside(booth, root.Position, 2.2) then
			moveCharacter(player, ch, facing)
			hum:MoveTo(facing.Position)
		end
		for _, other in ipairs(Players:GetPlayers()) do
			local oc = other.Character
			local orp = oc and oc:FindFirstChild("HumanoidRootPart")
			if other ~= player and orp and not slotLookup(other) and inDoorway(booth, orp.Position) then
				local _, sideways, up = forwardOf(booth, orp.Position)
				local spot = pivot:PointToWorldSpace(Vector3.new(math.clamp(sideways, -1.5, 1.5), up, -5.8))
				moveCharacter(other, oc, CFrame.lookAt(spot, spot + fwd))
			end
		end
	end)
end

---------------------------------------------------------------- watchdog
-- A safety net for whatever slipped past the moves above (lag, a glitch through the glass):
-- twice a second, nobody may stand inside a booth they are not in, and nobody in a booth may
-- stand outside it. Skipped while a walk-in of theirs is under way (WALK_GRACE at most),
-- while a door is up, while riding, seated or dead, and from GO! on.
local KEEP_IN    = 2.5      -- out past the glass's inner face (2.45) counts as outside
local WALK_GRACE = 6
local function lift(ch, hum, root)
	if hum.RigType == Enum.HumanoidRigType.R6 then return 3 end
	return hum.HipHeight + root.Size.Y / 2
end
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, plr in ipairs(Players:GetPlayers()) do
			local w = walking[plr]
			local ch = plr.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if not (w and os.clock() - w.t < WALK_GRACE) and hum and root and hum.Health > 0
				and not hum.Sit and not root:FindFirstChild("ScooterRiderWeld") then
				local slot = slotLookup(plr)
				if slot then
					-- in a booth: back inside it, facing out
					local st = slot.station
					local part = st and st.Parts and st.Parts[slot.role]
					local booth = part and boothOf(part)
					if booth and st.Phase ~= "Launched" and booth:GetAttribute("DoorOpen") ~= true
						and not isInside(booth, root.Position, KEEP_IN) then
						local pivot = booth.WorldPivot
						local spot = pivot:PointToWorldSpace(Vector3.new(0, 0.3 + lift(ch, hum, root), 0))
						moveCharacter(plr, ch, CFrame.lookAt(spot, spot + pivot.LookVector))
					end
				else
					-- in no booth: out of any it stands in, to just in front of its door
					for _, booth in ipairs(CollectionService:GetTagged("CapsuleBooth")) do
						if booth:IsDescendantOf(workspace) and booth:FindFirstChild("Door")
							and booth:GetAttribute("DoorOpen") ~= true and isInside(booth, root.Position, KEEP_IN) then
							local pivot = booth.WorldPivot
							local _, sideways, up = forwardOf(booth, root.Position)
							local spot = pivot:PointToWorldSpace(Vector3.new(math.clamp(sideways, -1.5, 1.5), up, -5.8))
							moveCharacter(plr, ch, CFrame.lookAt(spot, spot + pivot.LookVector))
							break
						end
					end
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player) walking[player] = nil end)

return CapsuleEntry
