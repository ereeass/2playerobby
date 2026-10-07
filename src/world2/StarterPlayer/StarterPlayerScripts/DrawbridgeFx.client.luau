-- Drawbridge (Workspace > Drawbridge Road), run on THIS player's machine only.
-- The bridge is raised for everyone. When the scooter you're riding (or you, on foot) rolls
-- over the button on the side lane, the bridge lowers on YOUR screen only - so a pair
-- riding together both see it come down (each of their machines spots the same scooter on
-- the button), and everyone else's stays up. The driver's machine drives the scooter, so it
-- really can cross on the lowered bridge.
--   down     swings down and bounces as it lands (LowerTime)
--   hold     stays down for HoldTime; the tower lamps go green, then blink amber near the end
--   up       winches back up (RaiseTime). Hitting the button again while it's down restarts
--            the hold.
-- Tuning: RaisedDeg / LowerTime / HoldTime / RaiseTime attributes on the Drawbridge Road model.

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local player  = Players.LocalPlayer
local WARN    = 2          -- seconds of blinking before it goes back up
local RED     = Color3.fromRGB(230, 50, 40)
local GREEN   = Color3.fromRGB(70, 220, 90)
local AMBER   = Color3.fromRGB(255, 180, 40)

local bridges = {}

local function add(m)
	if bridges[m] or not m:IsA("Model") then return end
	local hinge, leaf = m:FindFirstChild("Hinge"), m:FindFirstChild("Leaf")
	local button = m:FindFirstChild("Button")
	local zone = button and button:FindFirstChild("Zone")
	if not (hinge and leaf and zone) then return end
	local raised = math.rad(m:GetAttribute("RaisedDeg") or 78)
	-- every leaf part relative to the hinge with the bridge DOWN (it's stored raised)
	local parts = {}
	for _, p in ipairs(leaf:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, { p, CFrame.Angles(-raised, 0, 0) * hinge.CFrame:ToObjectSpace(p.CFrame) })
		end
	end
	local chains = {}
	local towers, chainM = m:FindFirstChild("Towers"), m:FindFirstChild("Chains")
	for _, side in ipairs({ "L", "R" }) do
		local a = towers and towers:FindFirstChild("Anchor" .. side)
		local b = leaf:FindFirstChild("ChainEnd" .. side)
		local ch = chainM and chainM:FindFirstChild("Chain" .. side)
		if a and b and ch then table.insert(chains, { a, b, ch }) end
	end
	local lamps = {}
	for _, p in ipairs(m:GetDescendants()) do if p.Name == "Lamp" and p:IsA("BasePart") then table.insert(lamps, p) end end
	local top = button:FindFirstChild("Top")
	bridges[m] = {
		model = m, hinge = hinge, zone = zone, parts = parts, chains = chains, lamps = lamps,
		top = top, topCF = top and top.CFrame, topColor = top and top.Color,
		raised = raised, angle = raised, state = "up", t0 = 0, from = raised, holdStart = 0,
	}
end

local function riderBody()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	-- riding? then it's the scooter that presses the button
	local weld = root:FindFirstChild("ScooterRiderWeld")
	return (weld and weld.Part0) or root
end

local function inZone(zone, pos)
	local p = zone.CFrame:PointToObjectSpace(pos)
	local h = zone.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function apply(b)
	local cf = b.hinge.CFrame * CFrame.Angles(b.angle, 0, 0)
	for _, pr in ipairs(b.parts) do pr[1].CFrame = cf * pr[2] end
	for _, c in ipairs(b.chains) do
		local a, e = c[1].Position, c[2].Position
		c[3].Size = Vector3.new(0.4, 0.4, math.max(0.1, (e - a).Magnitude))
		c[3].CFrame = CFrame.lookAt((a + e) / 2, e)
	end
end

local function lamps(b, col)
	for _, l in ipairs(b.lamps) do l.Color = col end
end

local function press(b, now)
	if b.state == "down" then
		b.holdStart = now                   -- another press keeps it down a bit longer
	elseif b.state ~= "lowering" then
		b.state, b.t0, b.from = "lowering", now, b.angle
		Sfx.Play("Drawbridge", b.hinge)
	end
end

for _, m in ipairs(CollectionService:GetTagged("Drawbridge")) do add(m) end
CollectionService:GetInstanceAddedSignal("Drawbridge"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("Drawbridge"):Connect(function(m) bridges[m] = nil end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local body = riderBody()
	for m, b in pairs(bridges) do
		if not m.Parent or not b.hinge.Parent then bridges[m] = nil continue end
		local lowerT = m:GetAttribute("LowerTime") or 1.4
		local holdT  = m:GetAttribute("HoldTime") or 6
		local raiseT = m:GetAttribute("RaiseTime") or 2
		if body and inZone(b.zone, body.Position) then press(b, now) end

		if b.state == "lowering" then
			local a = math.clamp((now - b.t0) / lowerT, 0, 1)
			b.angle = b.from * (1 - TweenService:GetValue(a, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out))
			if a >= 1 then b.state, b.angle, b.holdStart = "down", 0, now end
			lamps(b, GREEN)
			apply(b)
		elseif b.state == "down" then
			local left = holdT - (now - b.holdStart)
			if left <= 0 then
				b.state, b.t0 = "raising", now
				Sfx.Play("Drawbridge", b.hinge)
			elseif left <= WARN then
				lamps(b, (math.floor(now * 6) % 2 == 0) and AMBER or GREEN)
			else
				lamps(b, GREEN)
			end
		elseif b.state == "raising" then
			local a = math.clamp((now - b.t0) / raiseT, 0, 1)
			b.angle = b.raised * TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			lamps(b, AMBER)
			apply(b)
			if a >= 1 then b.state, b.angle = "up", b.raised; lamps(b, RED) end
		end

		-- the button turns green (on this player's screen) while the bridge is (coming) down
		if b.top then
			local on = b.state ~= "up"
			b.top.Color = on and GREEN or b.topColor
		end
	end
end)
