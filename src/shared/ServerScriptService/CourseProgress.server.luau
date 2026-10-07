--=====================================================================
-- CourseProgress   (server)
--
-- How far along the course every player is, for the progress bar at the top of the screen
-- (StarterGui.CourseProgressGui). The server works it out; clients only draw it:
--   player:GetAttribute("CourseProgress")   0 (the start gate) .. 1 (the finish)
-- written every UPDATE_EVERY seconds, and only when it has moved.
--
-- Measured along the course's own line (CoursePath: the road's real length, so a long
-- section counts for more than a short one) at the ride's SCOOTER - one position for the
-- pair, so the Driver and the Motor always show together - and only within the stretch the
-- ride has earned: from the last checkpoint it reached (CheckpointProgress) to the next. So
-- it follows the scooter both ways (reversing), but never runs ahead of a checkpoint that
-- has not been reached, and only a finish makes it exactly 1:
--   in the lobby or a booth        0
--   riding                         where the scooter is on the line
--   down (the death popup)         where it went in, until the ride ends
--   finished                       1 (RunTimer's finish, or the scooter at the finish line
--                                  on a ride that started further on), for FINISH_HOLD
--                                  seconds - back in the lobby too - or until a new ride
-- Nothing here changes a ride, a checkpoint or a run.
--=====================================================================

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem      = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager        = require(ScooterSystem:WaitForChild("RideManager"))
local CheckpointProgress = require(ScooterSystem:WaitForChild("CheckpointProgress"))
local RunTimer           = require(ScooterSystem:WaitForChild("RunTimer"))
local Checkpoints        = require(ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Checkpoints"))
local CoursePath         = require(script:WaitForChild("CoursePath"))

local ATTRIBUTE    = "CourseProgress"
local UPDATE_EVERY = 0.2    -- seconds
local MIN_CHANGE   = 0.0005 -- smaller moves are not sent (0.05% of the course)
local BACK_SLACK   = 30     -- studs a ride may be measured behind the checkpoint it last reached
local FINISH_NEAR  = 4      -- studs from the end of the line that count as over the finish
local FINISH_HOLD  = 10     -- seconds a finisher stays at 100%

---------------------------------------------------------------- the line
local P = CoursePath.Points
local S = { 0 }             -- studs along the line at each point
for i = 2, #P do S[i] = S[i - 1] + (P[i] - P[i - 1]).Magnitude end
local LENGTH = S[#P]
local MAX_ORDER = Checkpoints.MaxOrder()

local function checkpointAt(order)
	return CoursePath.Checkpoints[order] or 0
end

-- the first point at or past `s`
local function indexAt(s)
	local lo, hi = 1, #P
	while lo < hi do
		local mid = (lo + hi) // 2
		if S[mid] < s then lo = mid + 1 else hi = mid end
	end
	return lo
end

-- studs along the line of the point on it nearest `pos`, looking only between sMin and sMax
local function measure(pos, sMin, sMax)
	local first = math.max(1, indexAt(sMin) - 1)
	local last = math.min(#P, indexAt(sMax))
	local bestS, bestD = sMin, math.huge
	for i = first, last - 1 do
		local a, b = P[i], P[i + 1]
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = (len2 > 0) and math.clamp((pos - a):Dot(ab) / len2, 0, 1) or 0
		local d = (a + ab * t - pos).Magnitude
		if d < bestD then
			bestD = d
			bestS = S[i] + (S[i + 1] - S[i]) * t
		end
	end
	return math.clamp(bestS, sMin, sMax)
end

---------------------------------------------------------------- rides
local lastValue = {}   -- [ride] = its last progress (kept while it is down)
local finished  = {}   -- [player] = { at = os.clock(), ride = ride }

local function markFinished(player, ride)
	if player and player.Parent == Players then finished[player] = { at = os.clock(), ride = ride } end
end

-- a timed run over the real finish line (both riders, whoever they are now)
RunTimer.RunCompleted:Connect(function(record)
	if type(record) ~= "table" then return end
	for _, p in ipairs({ record.Player1, record.Player2 }) do
		local player = type(p) == "table" and Players:GetPlayerByUserId(p.UserId or 0)
		if player then markFinished(player, RideManager.PlayerRide[player]) end
	end
end)

local function rideProgress(ride)
	if ride.Down then return lastValue[ride] or 0 end   -- in the water: where it went in
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return lastValue[ride] or 0 end
	local reached = CheckpointProgress.RideReached(ride) or Checkpoints.OrderOf(ride.CheckpointId) or 1
	reached = math.clamp(reached, 1, MAX_ORDER)
	if reached == 1 then
		-- from the start: nothing until the scooter is through the start gate (RunTimer's
		-- run is still "Waiting" at the spawn and on the way to the gate)
		local rider = ride.Driver or ride.Passenger
		local run = rider and RunTimer.GetRunForPlayer(rider)
		if run and run.Status == "Waiting" then
			lastValue[ride] = 0
			return 0
		end
	end
	local sMin = math.max(0, checkpointAt(reached) - BACK_SLACK)
	local sMax = (reached < MAX_ORDER) and checkpointAt(reached + 1) or LENGTH
	local s = measure(chassis.Position, sMin, sMax)
	if reached == MAX_ORDER and s >= LENGTH - FINISH_NEAR then
		-- over the finish line (a ride that started further on isn't timed, so RunTimer won't say)
		for _, plr in ipairs({ ride.Driver, ride.Passenger }) do
			if plr and not (finished[plr] and finished[plr].ride == ride) then markFinished(plr, ride) end
		end
	end
	local v = math.clamp(s / LENGTH, 0, 1)
	lastValue[ride] = v
	return v
end

local function set(player, v)
	local old = player:GetAttribute(ATTRIBUTE)
	if old == nil or v == 0 or v == 1 or math.abs(v - old) >= MIN_CHANGE then
		if old ~= v then player:SetAttribute(ATTRIBUTE, v) end
	end
end

local function update()
	local now = os.clock()
	local byRide = {}
	for _, ride in pairs(RideManager.Rides) do
		if not ride._ended then byRide[ride] = rideProgress(ride) end
	end
	for ride in pairs(lastValue) do
		if not byRide[ride] then lastValue[ride] = nil end   -- that ride is over
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local ride = RideManager.PlayerRide[player]
		local fin = finished[player]
		if fin and (now - fin.at > FINISH_HOLD or (ride and ride ~= fin.ride)) then
			finished[player], fin = nil, nil   -- the hold is over, or they have set off again
		end
		local v
		if fin then
			v = 1
		elseif ride and byRide[ride] then
			-- never 100% without a finish: at most the last hundredth of a percent short
			v = math.min(byRide[ride], 1 - 1e-4)
		else
			v = 0
		end
		set(player, v)
	end
end

Players.PlayerAdded:Connect(function(player) player:SetAttribute(ATTRIBUTE, 0) end)
for _, player in ipairs(Players:GetPlayers()) do player:SetAttribute(ATTRIBUTE, 0) end
Players.PlayerRemoving:Connect(function(player) finished[player] = nil end)

task.spawn(function()
	while true do
		local ok, err = pcall(update)
		if not ok then warn("[CourseProgress] " .. tostring(err)) end
		task.wait(UPDATE_EVERY)
	end
end)
