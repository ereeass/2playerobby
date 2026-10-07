-- Stone Sweeper: three stone rollers sweep round the platform's carved guardian hub and
-- SHOVE whatever they catch along the way they're turning. Nothing dies from them:
--   Scooter   the server takes the scooter over for a moment, pushes it along the sweep
--             (and a little outward and up), then hands it straight back to its driver.
--             Pushed off the edge, it falls like anywhere else.
--   On foot   the character is shoved the same way.
-- The arms turn off the shared server clock (workspace:GetServerTimeNow()), so nothing is
-- replicated while they move: this works out where each arm is and does the push checks,
-- and StarterPlayerScripts.SweeperFx turns (and rolls) the same arms smoothly on every
-- player's screen. Sizes follow the model's scale.
-- Tuning: attributes on this model
--   TurnTime  seconds for one full turn (lower = faster)     Phase  offset in seconds
--   Push      studs/s of the shove

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris     = game:GetService("Debris")

local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local model  = script.Parent
local centre = model:WaitForChild("Centre")
local arms   = model:WaitForChild("Arms")

-- at scale 1
local ARM_Y     = 1.35               -- roller centre above the floor
local ARM_FROM  = 4.4                -- studs from the middle where the roller starts
local ARM_TO    = 19.24              -- ...and ends (shortened so the tips clear the spinplank)
local ARM_THICK = 3                  -- a touch fatter than the 2.7 roller

local OUTWARD   = 0.35               -- how much of the shove points away from the hub
local LIFT      = 10                 -- studs/s up, so it slides off the floor cleanly
local HOLD      = 0.2                -- seconds the server keeps the scooter while shoving it
local AGAIN     = 0.7                -- seconds before the same scooter/person can be shoved again

local angles = {}
for _, a in ipairs(arms:GetChildren()) do table.insert(angles, a:GetAttribute("Angle") or 0) end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { model }

local pushed = setmetatable({}, { __mode = "k" })   -- [ride or player] = os.clock()

local function driverOf(ride)
	for _, h in pairs(ride.Riders or {}) do
		if h.Role == "Driver" and h.Player then return h.Player end
	end
end

local function pushScooter(ride, v)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	pcall(function() chassis:SetNetworkOwner(nil) end)
	local t, conn = 0, nil
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		-- a Skip Stage is moving this scooter (ScooterSystem.SkipStage): the shove stops at once,
		-- so it can't carry on at the new spot and fling it; the skip hands it back itself
		if ride.SkipMoving then conn:Disconnect() return end
		if not chassis.Parent or t > HOLD then
			conn:Disconnect()
			-- give it back to the driver, who steers it again straight away
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

local function pushCharacter(character, v)
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

local function shoveFrom(p, dir)
	local speed = model:GetAttribute("Push") or 32
	local v = dir * speed + Vector3.new(0, LIFT, 0)
	local now = os.clock()
	-- a scooter on a ride?
	local m = p:FindFirstAncestorOfClass("Model")
	while m and m.Parent ~= scooters do m = m:FindFirstAncestorOfClass("Model") end
	local ride = m and RideManager.Rides[m]
	local plr
	if not ride then
		local c = p:FindFirstAncestorOfClass("Model")
		while c and not Players:GetPlayerFromCharacter(c) do c = c:FindFirstAncestorOfClass("Model") end
		plr = c and Players:GetPlayerFromCharacter(c)
		ride = plr and RideManager.PlayerRide[plr]
		if not ride and plr then
			if now - (pushed[plr] or 0) > AGAIN then
				pushed[plr] = now
				pushCharacter(c, v)
			end
			return
		end
	end
	if ride and not ride._ended and not ride.Down and not ride.SkipMoving and now - (pushed[ride] or 0) > AGAIN then
		pushed[ride] = now
		pushScooter(ride, v)
	end
end

RunService.Heartbeat:Connect(function()
	local turn  = model:GetAttribute("TurnTime") or 8
	local phase = model:GetAttribute("Phase") or 0
	local sc    = model:GetScale()
	-- wrap the (huge) clock into one turn first: a CFrame angle only keeps float precision
	-- for small numbers
	local a = (((workspace:GetServerTimeNow() + phase) % turn) / turn) * math.pi * 2
	local from, to = ARM_FROM * sc, ARM_TO * sc
	local len = to - from
	for _, th in ipairs(angles) do
		local cf = centre.CFrame * CFrame.Angles(0, a + th, 0) * CFrame.new(from + len / 2, ARM_Y * sc, 0)
		local parts = workspace:GetPartBoundsInBox(cf, Vector3.new(len, ARM_THICK * sc, ARM_THICK * sc), params)
		for _, p in ipairs(parts) do
			-- which way the arm is moving where it touched: round the hub, plus a bit outward
			local r = centre.CFrame:PointToObjectSpace(p.Position)
			local flat = Vector3.new(r.X, 0, r.Z)
			if flat.Magnitude > 0.1 then
				local out = flat.Unit
				local tangent = Vector3.new(out.Z, 0, -out.X)
				local dir = centre.CFrame:VectorToWorldSpace((tangent + out * OUTWARD).Unit)
				shoveFrom(p, dir)
			end
		end
	end
end)
