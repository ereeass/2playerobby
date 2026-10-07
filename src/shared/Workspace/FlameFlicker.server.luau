local TweenService = game:GetService("TweenService")
for _, p in ipairs(script.Parent:GetDescendants()) do
	if p:IsA("BasePart") and p.Name == "Flame" then
		local info = TweenInfo.new(0.35 + math.random() * 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random() * 0.3)
		TweenService:Create(p, info, { Size = p.Size * 1.2, Transparency = 0.35 }):Play()
	end
end
