--=====================================================================
-- FinishCutscene / Lock
--
-- Everything the cutscene takes from the player for its few seconds - each piece handed
-- to the session with how to give it back, so it comes back even if the cutscene fails
-- half-way.
--   Controls  Cinematic (ReplicatedStorage.ScooterSystem): RideGui.Controller sends the
--             scooter no steer and brakes it to a stop, whatever is held; horn and
--             pedals let go; the character's own controls stay off. Roblox's camera
--             input (the PlayerModule's CameraContext: mouse look, wheel, touch,
--             gamepad, Shift-lock) is switched off and every movement, camera and
--             ride key is swallowed above everything (ContextActionService), the
--             pointer hidden, Roblox's touch controls hidden, and the menus locked
--             (UITemplates.Menus: a MODAL screen - the open menu closes, none opens).
--             opts.ShowPointer: the pointer stays (the intro's SKIP button).
--   Hud       every other screen of the player's is put away (and put back, unless
--             something else changed it meanwhile), plus Config.HideCoreGui
--   Ride      the real scooter and its riders turn invisible on this machine only
--             (LocalTransparencyModifier; its trails and sparkles paused), and the
--             partner's name tag hides: only the cinematic copy is seen. Nothing about
--             them changes anywhere else.
-- Each cutscene holds all of it under its own key, so two at once (a nuke over a troll)
-- never hand anything back while the other still plays; camera input, touch controls and
-- the pointer are shared with the death popup and the windows (ScooterSystem.ControlHolds)
-- and come back only when the last of them lets go.
--=====================================================================

local Players              = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService     = game:GetService("UserInputService")
local StarterGui           = game:GetService("StarterGui")
local RS                   = game:GetService("ReplicatedStorage")

local Cinematic    = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Cinematic"))
local ControlHolds = require(RS:WaitForChild("ScooterSystem"):WaitForChild("ControlHolds"))
local Menus        = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))

local Lock = {}

local KEY  = "FinishCutscene"             -- each session holds as KEY#n, SINK#n
local SINK = "FinishCutsceneNoControls"
local serial = 0

-- swallowed while it plays: driving, walking, the horn, and every camera control
local SWALLOW = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.H,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
	Enum.KeyCode.I, Enum.KeyCode.O, Enum.KeyCode.Comma, Enum.KeyCode.Period,
	Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL2,
	Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL3, Enum.KeyCode.ButtonR3,
	Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight,
	Enum.UserInputType.MouseWheel, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseMovement,
	Enum.UserInputType.Touch,
}

function Lock.Controls(session, opts)
	opts = opts or {}
	serial += 1
	local key, sink = KEY .. "#" .. serial, SINK .. "#" .. serial

	Cinematic.Begin(key)
	session:Add("ride controls", function() Cinematic.End(key) end)

	-- Roblox's camera input (ContextActionService can't block it, so its context goes
	-- off), the touch controls and the pointer
	local holds = { "CameraInput", "TouchControls" }
	if not opts.ShowPointer then table.insert(holds, "Pointer") end
	session:Add("camera input, touch controls, pointer", function()
		ControlHolds.Release(key)
		-- always back to a free pointer, never the lock it had when the cutscene began (a
		-- right-drag or first-person lock from then would be stuck with nothing to undo it);
		-- Shift-lock / first person set their own lock again as soon as the camera is back
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	ControlHolds.Hold(key, holds)

	ContextActionService:BindActionAtPriority(sink, function() return Enum.ContextActionResult.Sink end,
		false, Enum.ContextActionPriority.High.Value + 200, table.unpack(SWALLOW))
	session:Add("keys", function() ContextActionService:UnbindAction(sink) end)

	Menus.Modal(key, true)
	session:Add("menus", function() Menus.Modal(key, false) end)
end

-- keep: the cutscene's own screen
function Lock.Hud(session, playerGui, keep, coreGui)
	local hidden = {}
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui ~= keep and gui.Enabled then
			local entry = { gui = gui, touched = false }
			gui.Enabled = false
			-- something else showing or hiding it meanwhile has the last word
			entry.conn = gui:GetPropertyChangedSignal("Enabled"):Connect(function() entry.touched = true end)
			table.insert(hidden, entry)
		end
	end
	local core = {}
	for _, name in ipairs(coreGui or {}) do
		local okType, kind = pcall(function() return Enum.CoreGuiType[name] end)
		if okType and kind then
			local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
			if ok and on and pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false) then
				table.insert(core, kind)
			end
		end
	end
	session:Add("HUD", function()
		for _, entry in ipairs(hidden) do
			entry.conn:Disconnect()
			if entry.gui.Parent and not entry.touched then entry.gui.Enabled = true end
		end
		for _, kind in ipairs(core) do pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true) end
	end)
end

-- ride: { Scooter, Riders = { { Character, Humanoid, Player } } }
function Lock.Ride(session, ride)
	local saved = {}   -- [part or decal] = its LocalTransparencyModifier; [effect] = true (was on)
	local function hide(model)
		if not (model and model.Parent) then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				if saved[d] == nil then saved[d] = d.LocalTransparencyModifier end
				d.LocalTransparencyModifier = 1
			elseif (d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")) and d.Enabled then
				saved[d] = true
				d.Enabled = false
			end
		end
	end
	hide(ride.Scooter)
	local names = {}
	for _, r in ipairs(ride.Riders) do
		hide(r.Character)
		local hum = r.Humanoid
		if hum and hum.Parent and r.Player ~= Players.LocalPlayer then
			names[hum] = hum.DisplayDistanceType
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	session:Add("the real ride", function()
		for inst, was in pairs(saved) do
			if inst.Parent then
				if was == true then inst.Enabled = true else inst.LocalTransparencyModifier = was end
			end
		end
		for hum, was in pairs(names) do
			if hum.Parent then hum.DisplayDistanceType = was end
		end
	end)
end

return Lock
