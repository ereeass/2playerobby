--=====================================================================
-- ScooterPodiums   (server)
--
-- Shows a scooter standing on each lobby podium (models tagged "ScooterPodium" with
-- a ScooterId attribute; the pad is the podium's PrimaryPart). The scooter is the
-- game's own: a copy of its visual-only menu preview (ScooterSelection builds those
-- from ServerStorage.ScooterModels), so the podium always matches the real model.
-- It stands centred on the pad (round: an upright Cylinder part), wheels on the top
-- face, and each player's ScooterPodiumSpin turns it slowly on the spot. It streams
-- in whole (Atomic), so the spinner always has every part of it.
-- Optional podium attributes: Yaw (degrees) turns the scooter on the pad; Still = true
-- keeps it standing still (ScooterPodiumSpin leaves it be; only its glass shimmers);
-- Shift (studs) slides it back along its length (negative: forward), for a long scooter
-- whose front would otherwise stick out of its case.
--
-- The podium's prompt (tag "ScooterPodiumPrompt") is handled by the player's
-- ScootersUI, exactly like the scooter's card: ScooterSelection.RewardAction, which
-- never grants (only ScooterSelection's grantReward does, when a session starts).
--
-- Ride effects: the display also gets the scooter's own effects, running as if it were
-- riding along at cruising speed (DRIVING_FX; false = the old plain display). Its speed
-- trails (the Chassis attachments named ...Trail, which ScooterFx only runs while riding)
-- are copied from the real model and kept on at their cruising rate, streaming out
-- behind the scooter; its always-on effects (sparkles, glows and lights held by invisible
-- parts, which the menu copy leaves out) come along too. Looks only: they're copies, on
-- an invisible FxRoot part where the chassis would be, so they turn with a turning display.
--=====================================================================

local CollectionService = game:GetService("CollectionService")
local RS                = game:GetService("ReplicatedStorage")

local previews = RS:WaitForChild("ScooterSystem"):WaitForChild("ScooterPreviews")

local DRIVING_FX  = true
local CRUISE      = 0.85                          -- share of top speed the display "rides" at
local DRIVE_SPEED = NumberRange.new(9, 14)        -- studs/s the trail streams back at
local DRIVE_DRAG  = 4                             -- ...slowing as it goes, like being left behind
-- the Ice Scooter's trail rates live in ScooterFx's TRAIL table (base, at top speed)
local ICE_TRAIL   = { IceFrost = { 3, 12 }, IceBits = { 4, 18 }, IceGlints = { 1, 5 } }

local Scooters      = require(RS.ScooterSystem:WaitForChild("Shared"):WaitForChild("Scooters"))
local ScooterModels = game:GetService("ServerStorage"):WaitForChild("ScooterModels")

local function addDrivingFx(display, id)
	local def = Scooters.Get(id)
	local real = def and ScooterModels:FindFirstChild(def.Model)
	local chassis = real and real:FindFirstChild("Chassis")
	if not chassis then return end
	-- the copies sit where they do on the real scooter (the menu copy shares its space)
	local root = Instance.new("Part")
	root.Name = "FxRoot"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch = true, false, false, false
	root.CFrame = chassis.CFrame
	root.Parent = display
	for _, a in ipairs(chassis:GetChildren()) do
		if a:IsA("Attachment") and not a.Name:match("Decals$") and a:FindFirstChildOfClass("ParticleEmitter") then
			local c = a:Clone()
			for _, x in ipairs(c:GetChildren()) do if not x:IsA("ParticleEmitter") then x:Destroy() end end
			if a.Name:match("Trail$") then
				c.CFrame = CFrame.new(c.Position)   -- faces the way the scooter does: Back = behind it
				for _, e in ipairs(c:GetChildren()) do
					local ice = ICE_TRAIL[e.Name]
					local base = e:GetAttribute("RateBase") or (ice and ice[1]) or 2
					local speed = e:GetAttribute("RateSpeed") or (ice and ice[2]) or 6
					e.Rate = base + speed * CRUISE
					e.EmissionDirection = Enum.NormalId.Back
					e.Speed = DRIVE_SPEED
					e.Drag = DRIVE_DRAG
				end
			end
			c.Parent = root
		end
	end
	-- always-on effects held by invisible parts in the look (the menu copy skips those)
	local cosmetic = real:FindFirstChild("Cosmetic")
	if cosmetic then
		for _, p in ipairs(cosmetic:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency >= 0.99
				and (p:FindFirstChildWhichIsA("Light", true) or p:FindFirstChildWhichIsA("ParticleEmitter", true)) then
				local c = p:Clone()
				for _, x in ipairs(c:GetDescendants()) do
					if x:IsA("JointInstance") or x:IsA("WeldConstraint") or x:IsA("Constraint") then x:Destroy() end
				end
				c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
				c.Parent = display
			end
		end
	end
end

-- the middle of the pad's top face: a block's, or a Cylinder's stood upright (its
-- round faces are its X ends)
local function padTop(pad)
	if pad:IsA("Part") and pad.Shape == Enum.PartType.Cylinder then
		return pad.CFrame * CFrame.Angles(0, 0, -math.pi / 2) * CFrame.new(0, pad.Size.X / 2, 0)
	end
	return pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0)
end

local function show(podium)
	local id = podium:GetAttribute("ScooterId")
	local pad = podium.PrimaryPart
	if type(id) ~= "string" or not pad then
		warn("[Scooter] podium " .. podium:GetFullName() .. " needs a ScooterId attribute and a PrimaryPart (its pad)")
		return
	end
	local src = previews:WaitForChild(id, 30)
	if not src then warn("[Scooter] no preview '" .. id .. "' for " .. podium:GetFullName()) return end
	local old = podium:FindFirstChild("Display")
	if old then old:Destroy() end

	local model = src:Clone()
	model.Name = "Display"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- the scooter's box, lined up with the pad and half its height above the pad's top
	local box, size = model:GetBoundingBox()
	-- (after measuring it: the effects' invisible holders must not move the scooter on the pad)
	if DRIVING_FX then addDrivingFx(model, id) end
	local top = padTop(pad)
	local yaw = math.rad(tonumber(podium:GetAttribute("Yaw")) or 180)
	local shift = tonumber(podium:GetAttribute("Shift")) or 0
	local want = top * CFrame.Angles(0, yaw, 0) * CFrame.new(0, size.Y / 2, shift)   -- the box ends up lined up with this: its +Z is the scooter's back
	model:PivotTo(want * box:ToObjectSpace(model:GetPivot()))
	model.Parent = podium
end

CollectionService:GetInstanceAddedSignal("ScooterPodium"):Connect(show)
for _, podium in ipairs(CollectionService:GetTagged("ScooterPodium")) do task.spawn(show, podium) end
