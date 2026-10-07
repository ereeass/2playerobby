-- Animates the capsule booths. Purely visual: the server decides the state
-- through two attributes on each booth model (ServerScriptService.ScooterSystem.
-- CapsuleEntry) and every client plays it:
--   DoorOpen  - the glass rolls up into the header, then back down (with a soft
--               shut sound as it lands: CapsuleFx.DoorClose)
--   Occupied  - the bottom lights fade from LightFree to LightBusy (green), and the
--               booth's smart screen (if it has one) swaps its role icon and bobbing
--               arrow for a tick (see "smart screens" below)
--             - and its OccupiedGlow (a green lit column over the booth floor and the
--               walkway in front of the door) fades from a soft white (free) to green,
--               with the occupant's headshot floating over the walkway (OccupantId, set
--               with Occupied)
-- A new tween on a part always cancels the previous one, so quick open/close
-- or enter/leave sequences never stack.
--
-- It also shapes how this client sees the booths' Enter prompts (bottom of file):
-- they only show in front of the glass door of a FREE booth (not while someone is in it
-- or walking in), and hovering one never stops the camera.

local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local RS                = game:GetService("ReplicatedStorage")

local BoothEntrance = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("BoothEntrance"))

local TAG = "CapsuleBooth"
local OPEN_INFO   = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local CLOSE_INFO  = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LIGHT_INFO  = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local ROLLED_UP   = 0.34    -- height of glass still showing under the header when open
local SCREEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TICK_INFO   = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOB_INFO    = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local GLOW_INFO   = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- how each OccupiedGlow piece looks while the booth is taken (busy) and while it is free
local GLOW_GREEN, GLOW_WHITE = Color3.fromRGB(60, 235, 95), Color3.fromRGB(235, 245, 255)
local GLOW = {
	Frame       = { busy = { BackgroundTransparency = 0, BackgroundColor3 = GLOW_GREEN },
	                free = { BackgroundTransparency = 0.45, BackgroundColor3 = GLOW_WHITE } },
	InsidePlate = { busy = { Transparency = 0.45, Color = GLOW_GREEN }, free = { Transparency = 0.9, Color = GLOW_WHITE } },
	PathPlate   = { busy = { Transparency = 0.55, Color = GLOW_GREEN }, free = { Transparency = 0.88, Color = GLOW_WHITE } },
	Light       = { busy = { Brightness = 1 }, free = { Brightness = 0 } },
	Picture     = { busy = { ImageTransparency = 0 }, free = { ImageTransparency = 1 } },
}

-- Played as the glass starts down. Its PlaybackRegion is cut so the shut in the
-- recording lands 0.25 s in, as the 0.3 s CLOSE_INFO tween settles. Change the
-- sound, volume or region on the DoorClose Sound itself.
local CLOSE_SOUND = script:WaitForChild("DoorClose")

-- Each booth's white outline (its WhiteOutline Highlight) draws at any distance, so
-- it showed across the map from the ride start. It fades with this player's
-- distance instead: full within OUTLINE_NEAR studs, gone past OUTLINE_FAR.
-- From the lobby spawn the farthest booth is 60 studs. Riding, they are hidden
-- outright: the Checkpoint 1 Parking Lot's nearest bays are only 62 studs from the
-- back booths, which show through the lobby's translucent barrier.
local OUTLINE_NEAR, OUTLINE_FAR = 62, 74

local booths = {}           -- [model] = state

local function run(b, inst, info, goal, instant)
	local old = b.tweens[inst]
	if old then old:Cancel(); b.tweens[inst] = nil end
	if instant then
		for k, v in pairs(goal) do inst[k] = v end
		return
	end
	local tw = TweenService:Create(inst, info, goal)
	b.tweens[inst] = tw
	tw:Play()
end

local function applyDoor(b, instant)
	if not b.glass then return end
	local open = b.model:GetAttribute("DoorOpen") == true
	local lift = b.h0 - ROLLED_UP
	local info = open and OPEN_INFO or CLOSE_INFO
	if open then
		run(b, b.glass, info, { Size = Vector3.new(b.s0.X, ROLLED_UP, b.s0.Z), CFrame = b.g0 + b.g0.UpVector * (lift / 2) }, instant)
	else
		run(b, b.glass, info, { Size = b.s0, CFrame = b.g0 }, instant)
		if not instant and b.closeSound then b.closeSound:Play() end
	end
	for _, mv in ipairs(b.movers) do
		run(b, mv.part, info, { CFrame = open and (mv.cf0 + b.g0.UpVector * lift) or mv.cf0 }, instant)
	end
end

local function applyLights(b, instant)
	local m = b.model
	local busy = m:GetAttribute("Occupied") == true
	local c = busy and (m:GetAttribute("LightBusy") or Color3.fromRGB(60, 235, 95))
		or (m:GetAttribute("LightFree") or Color3.fromRGB(45, 165, 255))
	for _, inst in ipairs(b.lights) do run(b, inst, LIGHT_INFO, { Color = c }, instant) end
	-- the occupant's headshot (it keeps the last one while fading out)
	local id = tonumber(m:GetAttribute("OccupantId")) or 0
	if busy and b.picture and id > 0 then
		b.picture.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(id)
	end
	for _, e in ipairs(b.glow) do
		local on = busy and not (e.inst == b.picture and id <= 0)
		run(b, e.inst, GLOW_INFO, on and e.busy or e.free, instant)
	end
end

-- the booth's OccupiedGlow pieces: what to fade, and to what
local function glowOf(b)
	local list = {}
	local g = b.model:WaitForChild("OccupiedGlow", 3)
	if not g then return list end
	for _, d in ipairs(g:GetDescendants()) do
		local kind = (d:IsA("ImageLabel") and d.Name == "Picture" and "Picture")
			or (d:IsA("Frame") and "Frame")
			or (d:IsA("BasePart") and GLOW[d.Name] and d.Name)
			or (d:IsA("PointLight") and "Light")
		if kind then
			if kind == "Picture" then b.picture = d end
			table.insert(list, { inst = d, busy = GLOW[kind].busy, free = GLOW[kind].free })
		end
	end
	return list
end

-- every visible shape in a screen group, with how solid it is when shown
local function shapesOf(group)
	local list = {}
	for _, d in ipairs(group:GetDescendants()) do
		if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then
			table.insert(list, { inst = d, prop = "BackgroundTransparency", base = d.BackgroundTransparency })
		elseif d:IsA("UIStroke") then
			table.insert(list, { inst = d, prop = "Transparency", base = d.Transparency })
		end
	end
	return list
end

local function remove(m)
	local b = booths[m]
	if not b then return end
	booths[m] = nil
	for _, c in ipairs(b.conns) do c:Disconnect() end
	for _, tw in pairs(b.tweens) do tw:Cancel() end
	if b.closeSound then b.closeSound:Destroy() end
end

local function add(m)
	if booths[m] or not m:IsA("Model") then return end
	local door   = m:WaitForChild("Door", 10)
	local lights = m:WaitForChild("Lights", 10)
	if not (door and lights) or not m:IsDescendantOf(workspace) then return end

	local b = { model = m, tweens = {}, conns = {}, movers = {}, lights = {} }
	b.outline = m:FindFirstChild("WhiteOutline")
	if b.outline then b.outlineT, b.pos = b.outline.OutlineTransparency, m:GetPivot().Position end
	local glass = door:WaitForChild("Glass", 5)
	if glass then
		-- the server never moves the door, so what streamed in is the closed state
		b.glass, b.g0, b.s0, b.h0 = glass, glass.CFrame, glass.Size, glass.Size.Y
		b.closeSound = CLOSE_SOUND:Clone()
		b.closeSound.Parent = glass
		for _, p in ipairs(door:GetChildren()) do
			if p:IsA("BasePart") and p ~= glass then table.insert(b.movers, { part = p, cf0 = p.CFrame }) end
		end
	end
	for _, d in ipairs(lights:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Light") then table.insert(b.lights, d) end
	end
	b.glow = glowOf(b)
	booths[m] = b

	applyDoor(b, true)
	applyLights(b, true)
	table.insert(b.conns, m:GetAttributeChangedSignal("DoorOpen"):Connect(function() applyDoor(b, false) end))
	table.insert(b.conns, m:GetAttributeChangedSignal("Occupied"):Connect(function() applyLights(b, false) end))
	table.insert(b.conns, m:GetAttributeChangedSignal("OccupantId"):Connect(function() applyLights(b, false) end))
	table.insert(b.conns, m.AncestryChanged:Connect(function()
		if not m:IsDescendantOf(workspace) then remove(m) end
	end))
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(m) task.spawn(add, m) end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, m in ipairs(CollectionService:GetTagged(TAG)) do task.spawn(add, m) end

---------------------------------------------------------------- smart screens
-- A booth's smart screen is its own model (tagged CapsuleScreen), so it can be
-- moved anywhere; its ObjectValue "Booth" names the booth it reports on. It holds
-- two layers: Waiting (the role icon and an arrow bobbing down into the booth, in
-- the brighter GlowGui so the bloom gives them a soft glow) while the booth is
-- free, and Done (a tick, in SignGui) once it is Occupied.
local SCREEN_TAG = "CapsuleScreen"
local screens = {}          -- [screen model] = state

local function applyScreen(s, instant)
	local busy = s.booth ~= nil and s.booth:GetAttribute("Occupied") == true
	-- (a SurfaceGui cannot fade a CanvasGroup, so each shape fades on its own)
	for _, e in ipairs(s.waiting) do run(s, e.inst, SCREEN_INFO, { [e.prop] = busy and 1 or e.base }, instant) end
	for _, e in ipairs(s.done) do run(s, e.inst, SCREEN_INFO, { [e.prop] = busy and e.base or 1 }, instant) end
	if s.tick then
		if busy and not instant then s.tick.Scale = 0.5 end
		run(s, s.tick, TICK_INFO, { Scale = 1 }, instant)
	end
end

local function bindBooth(s, booth)
	if s.boothConn then s.boothConn:Disconnect(); s.boothConn = nil end
	s.booth = booth
	if booth then
		s.boothConn = booth:GetAttributeChangedSignal("Occupied"):Connect(function() applyScreen(s, false) end)
	end
	applyScreen(s, true)
end

local function removeScreen(model)
	local s = screens[model]
	if not s then return end
	screens[model] = nil
	for _, c in ipairs(s.conns) do c:Disconnect() end
	if s.boothConn then s.boothConn:Disconnect() end
	for _, tw in pairs(s.tweens) do tw:Cancel() end
	if s.arrow then s.arrow.Position = s.arrowAt end   -- ready to bob from the same place
end

local function addScreen(model)
	if screens[model] or not model:IsA("Model") then return end
	local waiting, done = model:FindFirstChild("Waiting", true), model:FindFirstChild("Done", true)
	local ref = model:FindFirstChild("Booth")
	if not (waiting and done and ref) then return end
	local s = { tweens = {}, conns = {}, waiting = shapesOf(waiting), done = shapesOf(done), tick = done:FindFirstChildOfClass("UIScale") }
	screens[model] = s
	done.Visible = true   -- hidden in Studio; from here its shapes fade instead
	-- the arrow bobs gently, pointing into the booth
	local arrow = waiting:FindFirstChild("Arrow")
	if arrow then
		s.arrow, s.arrowAt = arrow, arrow.Position
		local bob = TweenService:Create(arrow, BOB_INFO, { Position = arrow.Position + UDim2.fromScale(0, 0.05) })
		s.tweens.bob = bob
		bob:Play()
	end
	-- the booth can stream in after its screen
	table.insert(s.conns, ref.Changed:Connect(function() bindBooth(s, ref.Value) end))
	table.insert(s.conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then removeScreen(model) end
	end))
	bindBooth(s, ref.Value)
end

CollectionService:GetInstanceAddedSignal(SCREEN_TAG):Connect(addScreen)
CollectionService:GetInstanceRemovedSignal(SCREEN_TAG):Connect(removeScreen)
for _, m in ipairs(CollectionService:GetTagged(SCREEN_TAG)) do addScreen(m) end

---------------------------------------------------------------- enter prompts
local player = Players.LocalPlayer

-- a booth's Enter prompt sits on its trigger part, which points at the booth model
local function boothFor(trigger)
	local ref = trigger and trigger:FindFirstChild("CapsuleModel")
	return ref and ref.Value
end

-- Front only. The prompts reach through the walls (RequiresLineOfSight is off so
-- the glass cannot hide them), so behind or beside a booth this client switches
-- them off. The server makes the same check (CapsuleEntry.CanEnterFrom); this is
-- only what the player sees. A booth someone is in (Occupied) or walking into (its
-- door is up: DoorOpen) has no prompt either - the server would turn the press down. Trigger parts stream in and out, so prompts are
-- tracked as they arrive.
local prompts = {}          -- [ProximityPrompt] = true
local function track(d)
	-- every prompt under CapsuleStations is a booth's; its booth is looked up each
	-- check, since the link can stream in after the prompt
	if d:IsA("ProximityPrompt") then prompts[d] = true end
end
task.spawn(function()
	local stations = workspace:WaitForChild("RideSystem"):WaitForChild("CapsuleStations")
	stations.DescendantAdded:Connect(track)
	for _, d in ipairs(stations:GetDescendants()) do track(d) end
end)

local nextCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextCheck then return end
	nextCheck = now + 0.1
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	for p in pairs(prompts) do
		if not p:IsDescendantOf(workspace) then
			prompts[p] = nil
		else
			local booth = boothFor(p.Parent)
			if booth and booth:IsDescendantOf(workspace) then
				local taken = booth:GetAttribute("Occupied") == true or booth:GetAttribute("DoorOpen") == true
				local want = not taken and BoothEntrance.IsInFront(booth, root.Position)
				if p.Enabled ~= want then p.Enabled = want end
			end
		end
	end
	local riding = root:FindFirstChild("ScooterRiderWeld") ~= nil   -- on a scooter (RiderAttach)
	for _, b in pairs(booths) do
		local o = b.outline
		if o then
			local fade = riding and 1
				or math.clamp(((b.pos - root.Position).Magnitude - OUTLINE_NEAR) / (OUTLINE_FAR - OUTLINE_NEAR), 0, 1)
			local t = b.outlineT + (1 - b.outlineT) * fade
			if o.OutlineTransparency ~= t then o.OutlineTransparency = t end
			if o.Enabled ~= (fade < 1) then o.Enabled = fade < 1 end
		end
	end
end)

-- Hovering a prompt must not stop the camera. The prompts are clickable, and
-- Roblox's default prompt UI catches the click with a full-size TextButton that is
-- Active - and an Active GUI under the cursor swallows mouse movement, so the
-- camera stopped turning whenever the prompt (floating mid-booth) passed under the
-- cursor. That button reads its click through InputBegan, which does not need
-- Active, so with Active off the prompt stays clickable and the camera keeps the
-- mouse. Only booth prompts are touched.
local function freeCamera(btn)
	local bb = btn:FindFirstAncestorOfClass("BillboardGui")
	if not bb then return end
	local function apply()
		if bb.Adornee and bb.Adornee:FindFirstChild("CapsuleModel") then
			pcall(function() btn.Active = false end)
			return true
		end
		return false
	end
	if not apply() and not bb.Adornee then
		-- the UI can be parented before it is pointed at the prompt
		local c
		c = bb:GetPropertyChangedSignal("Adornee"):Connect(function() c:Disconnect(); apply() end)
	end
end
local function watchPromptGui(g)
	if g.Name ~= "ProximityPrompts" then return end
	g.DescendantAdded:Connect(function(d) if d:IsA("GuiButton") then freeCamera(d) end end)
	for _, d in ipairs(g:GetDescendants()) do if d:IsA("GuiButton") then freeCamera(d) end end
end
local playerGui = player:WaitForChild("PlayerGui")
playerGui.ChildAdded:Connect(watchPromptGui)
for _, g in ipairs(playerGui:GetChildren()) do watchPromptGui(g) end
