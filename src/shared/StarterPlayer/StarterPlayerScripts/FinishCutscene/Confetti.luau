--=====================================================================
-- FinishCutscene / Confetti
--
-- Little pieces of paper, on this machine only: a light shower round the riders that
-- thickens once they cross, a spray from each side of the finish arch and a pop above
-- the riders at the line. Real (tiny) parts, so they tumble and catch the light, but
-- cheap: a fixed pool (Config.Confetti.Pool) made once and reused, nothing collides or
-- touches, and every moving piece is placed in ONE BulkMoveTo a frame. A piece that
-- reaches the ground lies there (the deck ends up sprinkled); one that runs out of
-- air time goes back to the pool. All of it goes with the scene.
--=====================================================================

local Confetti = {}
Confetti.__index = Confetti

local PARK = CFrame.new(0, -10000, 0)   -- where unused pieces wait, out of sight
local rng  = Random.new()

-- parent: where the pieces live (the scene's folder). groundParams: what the landing
-- rays look past.
function Confetti.new(parent, cfg, groundParams)
	local self = setmetatable({
		cfg = cfg, params = groundParams, free = {}, live = {}, t = 0,
		parts = {}, cfs = {},
	}, Confetti)
	local folder = Instance.new("Folder")
	folder.Name = "Confetti"
	for i = 1, cfg.Pool do
		local p = Instance.new("Part")
		p.Name = "Piece"
		p.Size = cfg.Size
		p.Color = cfg.Colors[(i - 1) % #cfg.Colors + 1]
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.CastShadow = false
		p.CFrame = PARK
		p.Parent = folder
		table.insert(self.free, { part = p })
	end
	folder.Parent = parent
	return self
end

-- all in use: the one that has been about longest (preferably one already on the ground)
function Confetti:_reuse()
	local best
	for piece in pairs(self.live) do
		if not best or (piece.resting and not best.resting)
			or (piece.resting == best.resting and piece.born < best.born) then
			best = piece
		end
	end
	if best then self.live[best] = nil end
	return best
end

-- one piece at `pos` flying at `vel`; `thrown`: sprayed, so it flies before the air slows it
function Confetti:Spawn(pos, vel, thrown)
	local piece = table.remove(self.free) or self:_reuse()
	if not piece then return end
	local cfg = self.cfg
	piece.pos, piece.vel = pos, vel
	piece.axis = rng:NextUnitVector()
	piece.angle = rng:NextNumber(0, math.pi * 2)
	piece.spin = rng:NextNumber(4, 11) * (rng:NextInteger(0, 1) * 2 - 1)
	piece.phase, piece.rate = rng:NextNumber(0, math.pi * 2), rng:NextNumber(2.2, 4)
	piece.flutter = rng:NextNumber(0.6, 1.6)
	piece.age, piece.life = 0, rng:NextNumber(cfg.Life[1], cfg.Life[2])
	piece.thrown = thrown and 0.45 or 0
	piece.resting = false
	piece.born = os.clock()
	local hit = workspace:Raycast(pos, Vector3.new(0, -60, 0), self.params)
	piece.floor = hit and (hit.Position.Y + cfg.Size.Y / 2) or (pos.Y - 60)
	self.live[piece] = true
end

-- `count` pieces drifting down round the riders (frame: the scooter's level frame)
function Confetti:Shower(frame, count)
	for _ = 1, count do
		local pos = frame * Vector3.new(rng:NextNumber(-3.5, 3.5), rng:NextNumber(6.5, 8.5), rng:NextNumber(-4, 3))
		self:Spawn(pos, Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1, 0.5), rng:NextNumber(-1.5, 1.5)), false)
	end
end

-- `count` pieces sprayed from `from`, up and over toward `toward`
function Confetti:Spray(from, toward, count)
	local dir = (toward - from)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.zero
	for _ = 1, count do
		local d = (dir * 0.75 + Vector3.yAxis * 0.85 + rng:NextUnitVector() * 0.3).Unit
		self:Spawn(from + rng:NextUnitVector() * 0.4, d * rng:NextNumber(14, 22), true)
	end
end

-- `count` pieces popped up and out from `at`
function Confetti:Pop(at, count)
	for _ = 1, count do
		local d = (Vector3.yAxis * 1.4 + rng:NextUnitVector()).Unit
		self:Spawn(at + rng:NextUnitVector() * 0.5, d * rng:NextNumber(8, 13), true)
	end
end

function Confetti:Step(dt)
	local cfg = self.cfg
	local parts, cfs = self.parts, self.cfs
	table.clear(parts)
	table.clear(cfs)
	self.t += dt
	local fall = Vector3.new(0, -cfg.Gravity * dt, 0)
	for piece in pairs(self.live) do
		if not piece.resting then
			piece.age += dt
			if piece.age >= piece.life then
				-- out of air time: back to the pool
				self.live[piece] = nil
				table.insert(self.free, piece)
				parts[#parts + 1], cfs[#cfs + 1] = piece.part, PARK
			else
				local drag = cfg.Drag
				if piece.thrown > 0 then
					piece.thrown -= dt
					drag *= 0.3
				end
				piece.vel = (piece.vel + fall) * math.exp(-drag * dt)
				-- paper flutters from side to side as it falls
				local wave = self.t * piece.rate
				local sway = Vector3.new(math.cos(piece.phase + wave), 0, math.sin(piece.phase * 1.3 + wave)) * piece.flutter
				local pos = piece.pos + (piece.vel + sway) * dt
				piece.angle += piece.spin * dt
				local cf
				if pos.Y <= piece.floor then
					-- landed: it lies flat where it fell
					pos = Vector3.new(pos.X, piece.floor, pos.Z)
					piece.resting = true
					cf = CFrame.new(pos) * CFrame.Angles(0, piece.angle, 0)
				else
					cf = CFrame.new(pos) * CFrame.fromAxisAngle(piece.axis, piece.angle)
				end
				piece.pos = pos
				parts[#parts + 1], cfs[#cfs + 1] = piece.part, cf
			end
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
end

return Confetti
