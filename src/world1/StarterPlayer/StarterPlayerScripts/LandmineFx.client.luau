-- A landmine's explosion sound (the Boom Sound in each Landmine model), on this machine
-- with no delay. Every Boom is loaded up front. The driver's machine simulates the
-- scooter, so it sees the wheels touch the mine first and plays the sound right then;
-- every other machine plays it when the server says the mine went off
-- (Remotes.LandmineBoom, from ServerScriptService.Landmines) - once, either way.
--
-- The two riders who set a mine off also see it blown away: it vanishes on THEIR
-- screens only (LocalTransparencyModifier never leaves this machine) and comes back
-- after GONE seconds. Everyone else sees it sitting there all along. Their camera
-- follows the scooter as it is thrown, until the death popup (StarterGui.DeathGui)
-- holds it still and, afterwards, gives it back to the character.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ContentProvider   = game:GetService("ContentProvider")
local RS                = game:GetService("ReplicatedStorage")

local Remotes = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local player  = Players.LocalPlayer

local ONCE = 1.5   -- seconds in which the same mine only sounds once
local GONE = 3     -- seconds the riders see their mine gone
local played = setmetatable({}, { __mode = "k" })   -- [mine] = os.clock() it last sounded
local hidden = setmetatable({}, { __mode = "k" })   -- [mine] = which hiding is the latest

-- this rider's camera rides along with their thrown scooter (the chassis they are
-- welded to, RiderAttach)
local function followScooter()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	local chassis = weld and weld.Part0
	local cam = workspace.CurrentCamera
	if not (chassis and cam) then return end
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = chassis
end

local function vanish(mine)
	followScooter()
	local token = (hidden[mine] or 0) + 1
	hidden[mine] = token
	local function set(value)
		for _, p in ipairs(mine:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = value end
		end
	end
	set(1)
	task.delay(GONE, function()
		if hidden[mine] == token and mine.Parent then set(0) end
	end)
end

local function play(mine)
	local last = played[mine]
	if last and os.clock() - last < ONCE then return end
	local boom = mine:FindFirstChild("Boom", true)
	if not boom then return end
	played[mine] = os.clock()
	boom:Play()
end

-- the scooter this player is welded to, if they are riding (RiderAttach)
local function myScooter()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0 and weld.Part0.Parent
end

-- a mine's parts can stream in after the mine itself, so wait for them
local function watch(mine)
	local base = mine:WaitForChild("Base", 60)
	local boom = base and base:WaitForChild("Boom", 60)
	if boom then ContentProvider:PreloadAsync({ boom }) end
	local trigger = mine:WaitForChild("Trigger", 60)
	if not trigger then return end
	trigger.Touched:Connect(function(hit)
		local scooter = myScooter()
		if not (scooter and hit:IsDescendantOf(scooter)) then return end
		local fresh = not played[mine] or os.clock() - played[mine] >= ONCE
		play(mine)
		if fresh then vanish(mine) end
	end)
end

CollectionService:GetInstanceAddedSignal("Landmine"):Connect(function(mine) task.spawn(watch, mine) end)
for _, mine in ipairs(CollectionService:GetTagged("Landmine")) do task.spawn(watch, mine) end

Remotes:WaitForChild("LandmineBoom").OnClientEvent:Connect(function(mine, riders)
	if typeof(mine) ~= "Instance" or not mine.Parent then return end
	local already = played[mine] and os.clock() - played[mine] < ONCE   -- this machine saw the touch itself
	play(mine)
	if not already and type(riders) == "table" and table.find(riders, player) then
		vanish(mine)   -- the rider whose machine did not see the touch (the passenger)
	end
end)
