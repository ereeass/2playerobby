-- Sweeps the lighthouse's lamp head and its two beams slowly round (SPIN_TIME seconds a turn).
local RunService = game:GetService("RunService")
local lamp = script.Parent:WaitForChild("Lamp")
local head = lamp:WaitForChild("LampHead")
local SPIN_TIME = 8
local centre = head.CFrame
local parts = {}
for _, p in ipairs(lamp:GetChildren()) do
	if p:IsA("BasePart") and (p.Name == "Beam" or p == head) then
		table.insert(parts, { part = p, rel = centre:ToObjectSpace(p.CFrame) })
	end
end
local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local a = ((os.clock() - t0) / SPIN_TIME) * math.pi * 2
	local cf = centre * CFrame.Angles(0, a, 0)
	for _, e in ipairs(parts) do e.part.CFrame = cf * e.rel end
end)
