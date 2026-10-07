--=====================================================================
-- RideTrollPrompt   (StarterPlayerScripts)
--
-- EXPLODE PLAYERS from ON a scooter: while this player is riding, every OTHER scooter close by
-- that has both its riders on gets an E prompt ("Explode Them!"). Pressing it asks the server
-- (Remotes.TrollRequest("Explode", scooter, "ride")) - the very same Explode Players troll as
-- the Troll window, through the same server code (ScooterSystem.TrollEffects): a saved free one
-- is used at once, otherwise Roblox's purchase window opens for its Developer Product, and the
-- receipt blows that duo up (or saves it as a free one if they got away). The server checks
-- everything again; this only decides where the prompt shows.
--   Riding    this player's root is welded to a scooter (RiderAttach's ScooterRiderWeld).
--   A target  another scooter in RideSystem.Scooters with two riders welded to it, within
--             PROMPT_RANGE, and no troll already playing on it (its Troll attribute).
-- The prompts are this machine's own (made here, never replicated).
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local RS                = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")

local player  = Players.LocalPlayer
local Remotes = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local request = Remotes:WaitForChild("TrollRequest")

local EFFECT       = "Explode"
local PROMPT_RANGE = 19      -- studs, this scooter to theirs (the server allows a little more)
local CHECK_EVERY  = 0.2     -- seconds between looking round
local WELD         = "ScooterRiderWeld"

-- B / Circle also closes menus and backs out of Roblox's UI cursor, so the prompt steps aside
-- while either has it
local Menus = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local function menuHasB()
	return GuiService.SelectedObject ~= nil or Menus.IsOpen() or Menus.IsModal() or Menus.IsBlocked()
end

local def
for _, e in ipairs(require(RS:WaitForChild("TrollFx"):WaitForChild("Effects"))) do
	if e.Id == EFFECT then def = e end
end

local prompts = {}   -- [chassis] = ProximityPrompt

-- the chassis a character is riding, or nil
local function chassisOf(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild(WELD)
	local chassis = weld and weld.Part0
	return (chassis and chassis.Parent) and chassis or nil
end

local busy = false
local function makePrompt(chassis)
	local at = Instance.new("Attachment")
	at.Name = "RideTrollPromptAt"
	at.Position = Vector3.new(0, 4, 0)
	at.Parent = chassis
	local p = Instance.new("ProximityPrompt")
	p.Name = "RideTrollPrompt"
	p.ActionText = "Explode Players"   -- just this, nothing else on the prompt
	p.ObjectText = ""
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonB   -- Circle / B on a controller
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = PROMPT_RANGE
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	p.Parent = at
	p.Triggered:Connect(function()
		if busy then return end
		local scooter = chassis.Parent
		-- the scooter model (RideSystem.Scooters.<name>) the chassis belongs to
		while scooter and scooter.Parent and scooter.Parent.Name ~= "Scooters" do scooter = scooter.Parent end
		if not scooter then return end
		busy = true
		task.spawn(function()
			pcall(request.InvokeServer, request, EFFECT, scooter, "ride")   -- a refusal says why itself (the red notice)
			busy = false
		end)
	end)
	prompts[chassis] = p
	return p
end

local function drop(chassis)
	local p = prompts[chassis]
	prompts[chassis] = nil
	if p and p.Parent then p.Parent:Destroy() end
end

local function scootersFolder()
	local sys = workspace:FindFirstChild("RideSystem")
	return sys and sys:FindFirstChild("Scooters")
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < CHECK_EVERY then return end
	acc = 0

	-- only ever while THIS player is on a ride's scooter: on foot (the lobby) nobody sees a prompt
	local mine = chassisOf(player.Character)
	local folder0 = scootersFolder()
	if mine and not (folder0 and mine:IsDescendantOf(folder0)) then mine = nil end
	local want = {}
	if mine and def then
		-- who is on which scooter
		local riders = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr ~= player and chassisOf(plr.Character)
			if c and c ~= mine then riders[c] = (riders[c] or 0) + 1 end
		end
		local folder = scootersFolder()
		for chassis, n in pairs(riders) do
			local scooter = chassis.Parent
			if n >= 2 and folder and chassis:IsDescendantOf(folder)
				and not (scooter and scooter:GetAttribute("Troll"))
				and (chassis.Position - mine.Position).Magnitude <= PROMPT_RANGE + 6 then
				want[chassis] = true
			end
		end
	end
	for chassis in pairs(prompts) do
		if not want[chassis] or not chassis.Parent then drop(chassis) end
	end
	for chassis in pairs(want) do
		if not prompts[chassis] then makePrompt(chassis) end
	end
	local free = not menuHasB()
	for _, p in pairs(prompts) do if p.Enabled ~= free then p.Enabled = free end end
end)
