-- Swinging spiked-log traps: each log hangs from its gantry and swings side to side across
-- the road. A log that hits you is deadly:
--   Run    a rider or their scooter hit by a log ends the run (DeathManager: SKIP / REVIVE).
--   Home   anyone NOT in a run who gets hit is sent back to the lobby, like KillZones.
-- The swing runs off the shared server clock (workspace:GetServerTimeNow()), so nothing is
-- replicated while it moves: this works out where each log is and does the knock checks,
-- and StarterPlayerScripts.SwingLogFx swings the same logs smoothly on every player's screen.
-- Sizes follow the model's scale.
-- Tuning: attributes on each LogTrapN model
--   SwingDeg  how far it swings each way     Period  seconds for a full there-and-back
--   Phase     offset in seconds, so the logs are out of step
-- and on this Swinging Logs model: Push (studs/s sideways), Lift (studs/s up)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris     = game:GetService("Debris")

local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local folder = script.Parent

-- at scale 1
local ROPE    = 13                   -- pivot to the log's middle
local LOG_BOX = Vector3.new(4.6, 4.6, 7.4)   -- log plus stakes
local HOLD    = 0.2
local AGAIN   = 0.8

local traps = {}
for _, m in ipairs(folder:GetChildren()) do
	local pivot = m:IsA("Model") and m:FindFirstChild("Pivot")
	if pivot then table.insert(traps, { model = m, pivot = pivot }) end
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { folder.Parent }

local knocked = setmetatable({}, { __mode = "k" })

local function driverOf(ride)
	for _, h in pairs(ride.Riders or {}) do
		if h.Role == "Driver" and h.Player then return h.Player end
	end
end

local function knockScooter(ride, v)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	pcall(function() chassis:SetNetworkOwner(nil) end)
	local t, conn = 0, nil
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if not chassis.Parent or t > HOLD then
			conn:Disconnect()
			local driver = driverOf(ride)
			if chassis.Parent and driver and driver.Parent then
				pcall(function() chassis:SetNetworkOwner(driver) end)
			end
			return
		end
		chassis.AssemblyLinearVelocity = v - Vector3.new(0, workspace.Gravity * t, 0)
	end)
	chassis.AssemblyLinearVelocity = v
end

local function knockCharacter(character, v)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local att = Instance.new("Attachment") att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VectorVelocity = v
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	Debris:AddItem(lv, HOLD)
	Debris:AddItem(att, HOLD)
end

local function knock(p, v)
	local now = os.clock()
	local m = p:FindFirstAncestorOfClass("Model")
	while m and m.Parent ~= scooters do m = m:FindFirstAncestorOfClass("Model") end
	local ride = m and RideManager.Rides[m]
	if not ride then
		local c = p:FindFirstAncestorOfClass("Model")
		while c and not Players:GetPlayerFromCharacter(c) do c = c:FindFirstAncestorOfClass("Model") end
		local plr = c and Players:GetPlayerFromCharacter(c)
		ride = plr and RideManager.PlayerRide[plr]
		if not ride and plr then
			if now - (knocked[plr] or 0) > 3 then
				local hum = c:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					knocked[plr] = now
					RideManager.SendHome(plr)
				end
			end
			return
		end
	end
	if ride and not ride._ended and not ride.Down then
		DeathManager.Hit(ride)
	end
end

-- angle (radians) and which way it's moving, from the shared clock
local function swingAt(m, now)
	local period = m:GetAttribute("Period") or 3.6
	local amp    = math.rad(m:GetAttribute("SwingDeg") or 55)
	local t      = (now + (m:GetAttribute("Phase") or 0)) % period   -- wrapped first: keeps precision
	local w      = t / period * math.pi * 2
	return amp * math.sin(w), math.cos(w)
end

RunService.Heartbeat:Connect(function()
	local now  = workspace:GetServerTimeNow()
	local push = folder:GetAttribute("Push") or 45
	local lift = folder:GetAttribute("Lift") or 14
	for _, tr in ipairs(traps) do
		local sc = tr.model:GetScale()
		local a, moving = swingAt(tr.model, now)
		-- only while it's actually swinging through (not hanging still at the top of a swing)
		if math.abs(moving) > 0.15 then
			local cf = tr.pivot.CFrame * CFrame.Angles(0, 0, a) * CFrame.new(0, -ROPE * sc, 0)
			local side = tr.pivot.CFrame.RightVector * (moving > 0 and 1 or -1)
			local v = Vector3.new(side.X, 0, side.Z).Unit * push + Vector3.new(0, lift, 0)
			for _, p in ipairs(workspace:GetPartBoundsInBox(cf, LOG_BOX * sc, params)) do knock(p, v) end
		end
	end
end)
