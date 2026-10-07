-- Re-applies Road3's gap, cracks and collapse holes (ServerScriptService.Road3Cuts) when
-- the game starts on a build of Road3 that hasn't had them cut yet.
local Road3Cuts = require(script.Parent:WaitForChild("Road3Cuts"))
if Road3Cuts.NeedsApply() then
	local ok, err = Road3Cuts.Apply()
	if not ok then warn("[Road3Cuts] " .. tostring(err)) end
end
