--=====================================================================
-- Preview   (ScootersUI)
--
-- A scooter turning in a card's ViewportFrame. It uses the server's visual-only
-- copy (ReplicatedStorage.ScooterSystem.ScooterPreviews.<Id>): visible parts only,
-- anchored, no collisions, joints or tuning, and it never enters the world. The
-- camera circles the model, so the turn is smooth and loops without a jump, and
-- the framing comes from the model's own parts: the camera sits as close as it
-- can while every part stays in frame all the way round, aimed at the middle of
-- what it sees, so any scooter fills its card.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local SPEED  = 0.85              -- radians a second: one full turn every ~7.4 s
local PITCH  = math.rad(12)      -- looking slightly down on it
local FOV    = 30
local MARGIN = 1.03              -- a hair of room around the scooter (it is the card's focus)
local FIT_SAMPLES = 48           -- angles checked round the turn when framing

-- the corners of every visible part, relative to the turning centre
local function corners(model, center)
	local pts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						table.insert(pts, cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)) - center)
					end
				end
			end
		end
	end
	return pts
end

-- where the camera sits, seen from the scooter, at turn angle a
local function viewDir(a)
	return Vector3.new(math.sin(a) * math.cos(PITCH), math.sin(PITCH), math.cos(a) * math.cos(PITCH))
end

-- the camera's turn, seen from the scooter, at sample i of FIT_SAMPLES
local function sampleRot(i)
	return CFrame.lookAt(viewDir(i / FIT_SAMPLES * math.pi * 2), Vector3.zero)
end

-- how far back the camera must be for every point to stay in frame all the way
-- round, aiming at the scooter's centre plus aim
local function fitDistance(pts, aim, tanH, tanV)
	local d = 0
	for i = 0, FIT_SAMPLES - 1 do
		local rot = sampleRot(i)
		for _, p in ipairs(pts) do
			local l = rot:VectorToObjectSpace(p - aim)   -- x right, y up, z toward the camera
			d = math.max(d, l.Z + math.abs(l.X) / tanH, l.Z + math.abs(l.Y) / tanV)
		end
	end
	return d
end

local Preview = {}
Preview.__index = Preview

function Preview.new(viewport, id, phase)
	local self = setmetatable({ viewport = viewport, angle = phase or 0, model = nil }, Preview)
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	self.cam = cam
	task.spawn(function()
		local folder = RS:WaitForChild("ScooterSystem"):WaitForChild("ScooterPreviews", 60)
		local src = folder and folder:WaitForChild(id, 60)
		if not src or not viewport.Parent then return end
		local m = src:Clone()
		local cf = m:GetBoundingBox()
		self.center = cf.Position
		self.points = corners(m, cf.Position)
		m.Parent = viewport
		self.model = m
		self:place()
	end)
	return self
end

-- just far enough back that every part fits from every side of its turn
-- (worked out once per viewport shape, not every frame)
function Preview:distance()
	local abs = self.viewport.AbsoluteSize
	local aspect = abs.Y > 1 and abs.X / abs.Y or 1.4
	if self.fitAspect and math.abs(self.fitAspect - aspect) < 0.01 then return self.fitDist end
	local tanV = math.tan(math.rad(FOV) / 2)
	local tanH = tanV * aspect
	-- aim at the height of the middle of what the camera sees all the way round,
	-- not the bounding box's middle (the wheels hang low and the stem is thin), so
	-- no space is wasted. Height only: it is the same from every side, so the
	-- scooter never drifts while it turns.
	local aim, d = Vector3.zero, 0
	for _ = 1, 3 do
		d = fitDistance(self.points, aim, tanH, tanV)
		local y0, y1 = math.huge, -math.huge
		for i = 0, FIT_SAMPLES - 1 do
			local rot = sampleRot(i)
			for _, p in ipairs(self.points) do
				local l = rot:VectorToObjectSpace(p - aim)
				local y = l.Y / (d - l.Z)
				y0, y1 = math.min(y0, y), math.max(y1, y)
			end
		end
		aim += Vector3.new(0, (y0 + y1) / 2 * d / math.cos(PITCH), 0)
	end
	d = fitDistance(self.points, aim, tanH, tanV)
	self.fitAspect, self.fitDist, self.aim = aspect, d * MARGIN, aim
	return self.fitDist
end

function Preview:place()
	if not self.model then return end
	local d = self:distance()
	local target = self.center + self.aim
	self.cam.CFrame = CFrame.lookAt(target + viewDir(self.angle) * d, target)
end

function Preview:step(dt)
	self.angle = (self.angle + SPEED * dt) % (math.pi * 2)
	self:place()
end

return Preview
