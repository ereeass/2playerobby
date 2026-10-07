-- Makes campfires flicker: the fire light pulses and each flame block gently
-- grows and shrinks from its base. Purely visual and local to each player; works
-- on any model tagged "Campfire" that has parts named "Flame" and a PointLight.

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local TAG = "Campfire"
local MAX_DISTANCE = 160      -- don't bother animating fires nobody can see

local fires = {}              -- [model] = { flames = {...}, light, base, seed }

local function track(f, d)
	if d:IsA("BasePart") and d.Name == "Flame" then
		table.insert(f.flames, { part = d, cf = d.CFrame, size = d.Size, phase = math.random() * 10 })
	elseif d:IsA("PointLight") and not f.light then
		f.light, f.base = d, d.Brightness
	end
end

local function add(m)
	if fires[m] then return end
	local f = { flames = {}, seed = math.random() * 100 }
	for _, d in ipairs(m:GetDescendants()) do track(f, d) end
	-- with streaming, pieces of the fire can arrive after the model itself
	f.conn = m.DescendantAdded:Connect(function(d) track(f, d) end)
	f.centre = m:GetPivot().Position
	fires[m] = f
end

local function remove(m)
	local f = fires[m]
	if not f then return end
	fires[m] = nil
	if f.conn then f.conn:Disconnect() end
	for _, fl in ipairs(f.flames) do
		if fl.part.Parent then fl.part.Size, fl.part.CFrame = fl.size, fl.cf end
	end
	if f.light then f.light.Brightness = f.base end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, m in ipairs(CollectionService:GetTagged(TAG)) do add(m) end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < 1 / 30 then return end           -- 30 updates a second is plenty
	acc = 0
	local cam = workspace.CurrentCamera
	local t = os.clock()
	for m, f in pairs(fires) do
		if not m.Parent then remove(m) continue end
		if cam and (cam.CFrame.Position - f.centre).Magnitude > MAX_DISTANCE then continue end
		if f.light then
			f.light.Brightness = f.base * (1 + 0.28 * math.noise(t * 5, f.seed))
		end
		for i, fl in ipairs(f.flames) do
			local k = 1 + 0.16 * math.noise(t * 7 + fl.phase, i, f.seed)
			local h = fl.size.Y * k
			fl.part.Size = Vector3.new(fl.size.X, h, fl.size.Z)
			-- keep the bottom of each flame where it was, so they grow upwards
			fl.part.CFrame = fl.cf * CFrame.new(0, (h - fl.size.Y) / 2, 0)
		end
	end
end)
