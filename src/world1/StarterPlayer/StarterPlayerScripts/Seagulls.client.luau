-- Seagulls at the Checkpoint 2 Beach Lot and the Sandy Lighthouse, on THIS machine only and
-- only while this player rides a scooter (driver or motor rider) near one of them - like the
-- other critters.
--   perched   stand on the umbrella, sandcastle, rocks and kerbs (beach) or the lamp gallery
--             railing and crates (lighthouse): look round, shuffle their wings. A scooter
--             rolling up (SCARE studs) sends them flapping up and away; they circle, and fly
--             back to their spot once it's clear. Now and then one also just takes off.
--   circling  a few glide round overhead all the time, flapping now and then.
-- Decoration only: no collision, touch or queries.
-- Sound (ReplicatedStorage.CritterSounds, very quiet): every so often one gull at a site
-- cries, and one sent off by a scooter gives a soft flap (sometimes a squawk).

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local NEAR  = 180     -- studs from a site for its gulls to exist
local SCARE = 22      -- a scooter this close sends a perched gull off
local S     = 1.25    -- gull size

local CritterSounds = require(game:GetService("ReplicatedStorage"):WaitForChild("CritterSounds"))

local player = Players.LocalPlayer
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local SITES = {
	{ name = "beach", model = "Checkpoint 2 Beach Lot", centre = Vector3.new(-382, 229, 557),
	  orbit = { c = Vector3.new(-380, 250, 557), r = { 18, 30 } }, circling = 2,
	  perches = { Vector3.new(-365.2, 0, 555.5), Vector3.new(-366.2, 0, 566.5), Vector3.new(-402, 0, 568),
	              Vector3.new(-370, 0, 534), Vector3.new(-360.2, 0, 574), Vector3.new(-407, 0, 557) } },
	{ name = "lighthouse", model = "Sandy Lighthouse", centre = Vector3.new(-270, 290, 668),
	  orbit = { c = Vector3.new(-270, 352, 668), r = { 26, 40 } }, circling = 3,
	  perches = { Vector3.new(-270.3, 0, 686.4), Vector3.new(-252.5, 0, 668), Vector3.new(-293, 0, 689) } },
}

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local WHITE, GREY, DARK, YELLOW, ORANGE = Color3.fromRGB(245, 246, 248), Color3.fromRGB(170, 178, 188), Color3.fromRGB(40, 42, 48), Color3.fromRGB(250, 205, 50), Color3.fromRGB(240, 150, 60)

local function bit(size, col, round, cls)
	local p = Instance.new(cls or "Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size * S, col, Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

local function makeGull(all)
	local g = { fixed = {}, wings = {}, legs = {} }
	local function fixed(size, col, at, round, cls)
		local p = bit(size, col, round, cls) table.insert(all, p) table.insert(g.fixed, { p = p, at = at * S })
	end
	fixed(Vector3.new(0.7, 0.68, 1.5), WHITE, Vector3.new(0, 0, 0), true)
	fixed(Vector3.new(0.56, 0.54, 0.62), WHITE, Vector3.new(0, 0.38, -0.72), true)
	fixed(Vector3.new(0.12, 0.14, 0.42), YELLOW, Vector3.new(0, 0.34, -1.18), false, "WedgePart")
	fixed(Vector3.new(0.08, 0.08, 0.08), DARK, Vector3.new(0.22, 0.46, -0.86), true)
	fixed(Vector3.new(0.08, 0.08, 0.08), DARK, Vector3.new(-0.22, 0.46, -0.86), true)
	fixed(Vector3.new(0.5, 0.14, 0.55), GREY, Vector3.new(0, 0.05, 0.9), false, "WedgePart")
	for _, side in ipairs({ 1, -1 }) do
		local w = bit(Vector3.new(1.5, 0.07, 0.62), GREY, true) table.insert(all, w)
		local tip = bit(Vector3.new(0.55, 0.075, 0.5), DARK, true) table.insert(all, tip)
		table.insert(g.wings, { side = side, w = w, tip = tip })
		local leg = bit(Vector3.new(0.07, 0.45, 0.07), ORANGE) table.insert(all, leg)
		table.insert(g.legs, { side = side, p = leg })
	end
	return g
end

-- put a gull at `cf` (its body middle). spread 0 = folded .. 1 = open; flap = wing angle
local function pose(g, cf, spread, flap, perched, out)
	for _, f in ipairs(g.fixed) do out.p[#out.p + 1] = f.p out.c[#out.c + 1] = cf * CFrame.new(f.at) end
	for _, w in ipairs(g.wings) do
		local s = w.side
		local hinge = cf * CFrame.new(s * 0.3 * S, 0.12 * S, -0.1 * S)
			* CFrame.Angles(0, -s * (1 - spread) * 1.35, 0) * CFrame.Angles(0, 0, s * flap - s * (1 - spread) * 0.25)
		out.p[#out.p + 1] = w.w out.c[#out.c + 1] = hinge * CFrame.new(s * 0.75 * S, 0, 0)
		out.p[#out.p + 1] = w.tip out.c[#out.c + 1] = hinge * CFrame.new(s * 1.55 * S, 0, 0.08 * S)
	end
	for _, l in ipairs(g.legs) do
		out.p[#out.p + 1] = l.p
		out.c[#out.c + 1] = perched and (cf * CFrame.new(l.side * 0.14 * S, -0.5 * S, 0.05 * S)) or (cf * CFrame.new(l.side * 0.1 * S, -0.2 * S, 0.7 * S) * CFrame.Angles(math.rad(80), 0, 0))
	end
end

local function bez(a, b, c, d, u)
	local v = 1 - u
	return a * v * v * v + b * 3 * v * v * u + c * 3 * v * u * u + d * u * u * u
end

local out = { p = {}, c = {} }
local t = 0

-- the top of whatever is under a perch spot
local function perchTop(site, p)
	local model = workspace:FindFirstChild(site.model)
	if not model then return nil end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(Vector3.new(p.X, site.centre.Y + 80, p.Z), Vector3.new(0, -220, 0), rp)
	return hit and hit.Position
end

local function orbitPoint(site, g, ang)
	local o = site.orbit
	return o.c + Vector3.new(math.cos(ang) * g.r, g.h + math.sin(t * 0.6 + g.phase) * 1.2, math.sin(ang) * g.r)
end

local function spawnSite(site)
	site.all, site.gulls = {}, {}
	site.cryTimer, site.scareQuiet = CritterSounds.Timer(3, 7), 0
	for _, spot in ipairs(site.perches) do
		local top = perchTop(site, spot)
		if top then
			table.insert(site.gulls, { g = makeGull(site.all), state = "perch", perch = top + Vector3.new(0, 0.55 * S, 0),
				yaw = math.random() * 6.28, phase = math.random() * 6, r = site.orbit.r[1] + math.random() * (site.orbit.r[2] - site.orbit.r[1]),
				h = math.random() * 6, speed = 0.35 + math.random() * 0.2, dir = math.random() < 0.5 and 1 or -1, calm = 0 })
		end
	end
	for i = 1, site.circling do
		table.insert(site.gulls, { g = makeGull(site.all), state = "circle", phase = math.random() * 6, ang = math.random() * 6.28,
			r = site.orbit.r[1] + math.random() * (site.orbit.r[2] - site.orbit.r[1]), h = math.random() * 8,
			speed = 0.3 + math.random() * 0.2, dir = math.random() < 0.5 and 1 or -1 })
	end
end

local function clearSite(site)
	for _, p in ipairs(site.all or {}) do p:Destroy() end
	site.all, site.gulls = nil, nil
end

local function scooterNear(pos, dist)
	for _, sc in ipairs(scooters:GetChildren()) do
		local pp = sc:IsA("Model") and sc.PrimaryPart
		if pp and (pp.Position - pos).Magnitude < dist then return pp.Position end
	end
end

RunService.Heartbeat:Connect(function(dt)
	t += dt
	local chassis = myChassis()
	table.clear(out.p) table.clear(out.c)
	for _, site in ipairs(SITES) do
		local near = chassis and (chassis.Position - site.centre).Magnitude < NEAR
		if not near then
			if site.gulls then clearSite(site) end
		else
			if not site.gulls then spawnSite(site) end
			site.scareQuiet -= dt
			if site.cryTimer:Due(dt) and #site.gulls > 0 then
				local b = site.gulls[math.random(#site.gulls)]
				CritterSounds.Play(b.g.fixed[2].p, "GullCry")
			end
			for _, b in ipairs(site.gulls) do
				if b.state == "perch" then
					local threat = scooterNear(b.perch, SCARE)
					if threat or math.random() < dt * 0.012 then
						-- one flap for a group taking off together, not one each
						if threat and site.scareQuiet <= 0 then
							site.scareQuiet = 1.5
							CritterSounds.Play(b.g.fixed[1].p, "GullFlap")
							if math.random() < 0.8 then CritterSounds.Play(b.g.fixed[2].p, "GullCry") end
						end
						-- take off: up and away from the scooter, then join the circle
						local away = threat and ((b.perch - threat) * Vector3.new(1, 0, 1)) or Vector3.new(math.cos(b.yaw), 0, math.sin(b.yaw))
						away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
						b.ang = math.atan2(b.perch.Z - site.orbit.c.Z, b.perch.X - site.orbit.c.X)
						local target = orbitPoint(site, b, b.ang + b.dir * 1.2)
						b.path = { b.perch, b.perch + away * 4 + Vector3.new(0, 5, 0), target - Vector3.new(0, 3, 0) + away * 6, target }
						b.state, b.u, b.dur, b.endAng = "fly", 0, 2.6, b.ang + b.dir * 1.2
						b.calm = 12 + math.random() * 12
					else
						local look = math.sin(t * 0.7 + b.phase) * 0.6 + (math.sin(t * 2.3 + b.phase) > 0.95 and 0.5 or 0)
						local stretch = math.sin(t * 0.25 + b.phase) > 0.97
						pose(b.g, CFrame.new(b.perch) * CFrame.Angles(0, b.yaw + look, 0) * CFrame.Angles(math.rad(-8), 0, 0),
							stretch and 0.8 or 0, stretch and 0.4 or 0, true, out)
					end
				end
				if b.state == "fly" or b.state == "land" then
					b.u = math.min(1, b.u + dt / b.dur)
					local P = b.path
					local pos = bez(P[1], P[2], P[3], P[4], b.u)
					local ahead = bez(P[1], P[2], P[3], P[4], math.min(1, b.u + 0.02))
					local dirv = ahead - pos
					if dirv.Magnitude < 0.01 then dirv = Vector3.new(math.cos(b.yaw or 0), 0, math.sin(b.yaw or 0)) end
					local landing = b.state == "land" and b.u > 0.8
					local flat = (dirv * Vector3.new(1, 0, 1))
					local cf = CFrame.lookAt(pos, pos + (landing and flat.Magnitude > 0.01 and flat or dirv))
					pose(b.g, cf, 1, math.sin(t * (landing and 22 or 16) + b.phase) * 0.7, landing, out)
					if b.u >= 1 then
						if b.state == "fly" then b.state, b.ang = "circle", b.endAng
						else
							b.state = "perch"
							if flat.Magnitude > 0.01 then b.yaw = math.atan2(-flat.X, -flat.Z) end
						end
					end
				elseif b.state == "circle" then
					b.ang += b.dir * b.speed * dt
					local pos = orbitPoint(site, b, b.ang)
					local nxt = orbitPoint(site, b, b.ang + b.dir * 0.05)
					local bank = CFrame.Angles(0, 0, b.dir * 0.35)
					local flapping = math.sin(t * 0.8 + b.phase) > 0.55
					pose(b.g, CFrame.lookAt(pos, nxt) * bank, 1, flapping and math.sin(t * 14 + b.phase) * 0.6 or 0.08, false, out)
					-- a perched gull goes home once it's clear there
					if b.perch then
						b.calm -= dt
						if b.calm <= 0 and not scooterNear(b.perch, SCARE * 1.6) then
							local fwd = (nxt - pos).Unit
							b.path = { pos, pos + fwd * 8, b.perch + Vector3.new(0, 6, 0) - fwd * 3, b.perch }
							b.state, b.u, b.dur = "land", 0, 3
						elseif b.calm <= 0 then
							b.calm = 4
						end
					end
				end
			end
		end
	end
	if #out.p > 0 then workspace:BulkMoveTo(out.p, out.c, Enum.BulkMoveMode.FireCFrameChanged) end
end)
