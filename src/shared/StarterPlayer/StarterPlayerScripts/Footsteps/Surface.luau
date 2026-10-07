-- Which footstep sound a surface gets: "Grass", "Dirt" or "Rock".
--
-- This map is built from Plastic parts with the "Studs" MaterialVariant (no terrain),
-- so Roblox's Material can't tell grass from dirt here - the part's COLOUR does:
--   green                 -> Grass  (lawns, cliff tops, capsule platform strips)
--   orange / tan earth    -> Dirt   (paths, path tiles, cliff sides, clearings)
--   everything else       -> Rock   (stone, grey, wood, metal, glass, unknown)
-- Real Roblox grass/dirt materials and terrain are recognised too, so terrain or
-- textured parts added later work without changes.
--
-- Exceptions: give a part, or any model/folder above it, a string attribute
-- "FootstepSurface" = "Grass", "Dirt" or "Rock". That wins over everything else.

local Surface = {}

local ATTRIBUTE = "FootstepSurface"
local KINDS = { Grass = true, Dirt = true, Rock = true }

-- Roblox materials (terrain or parts) that are grass or dirt by themselves
local MATERIALS = {
	[Enum.Material.Grass]      = "Grass",
	[Enum.Material.LeafyGrass] = "Grass",
	[Enum.Material.Ground]     = "Dirt",
	[Enum.Material.Mud]        = "Dirt",
	[Enum.Material.Sand]       = "Dirt",
}

-- Colour only decides on plain painted parts. A real material (Wood, Slate,
-- Concrete, Metal...) keeps its own character, i.e. Rock.
local PAINTED = {
	[Enum.Material.Plastic]       = true,
	[Enum.Material.SmoothPlastic] = true,
}

-- Earth colours too dull for the dirt rule below that ARE dirt on this map. Exact
-- matches only: the wood (logs, benches, crates, trunks) uses browns close to these.
local DIRT_COLOURS = {
	Color3.fromRGB(134, 100, 68), -- campfire clearing
}

local function byColour(colour)
	local h, s, v = colour:ToHSV()
	h *= 360
	if h >= 65 and h <= 170 and s >= 0.25 and v >= 0.2 then
		return "Grass"
	end
	-- saturated orange / tan / brown: the main paths, path tiles, cliff sides and the
	-- capsule platform path (hue 24-35, saturation 0.67+). Wood browns are duller
	-- (saturation 0.57 or less) and the red-brown picture frame sits below hue 18.
	if h >= 18 and h <= 40 and s >= 0.62 and v >= 0.35 then
		return "Dirt"
	end
	for _, dirt in ipairs(DIRT_COLOURS) do
		if math.abs(colour.R - dirt.R) + math.abs(colour.G - dirt.G) + math.abs(colour.B - dirt.B) < 0.02 then
			return "Dirt"
		end
	end
	return nil
end

-- part: the BasePart (or Terrain) stood on; material: its Material at that spot
function Surface.Classify(part, material)
	local node = part
	while node and node ~= workspace do
		local kind = node:GetAttribute(ATTRIBUTE)
		if KINDS[kind] then
			return kind
		end
		node = node.Parent
	end
	local kind = MATERIALS[material]
	if kind then
		return kind
	end
	if PAINTED[material] and not part:IsA("Terrain") then
		return byColour(part.Color) or "Rock"
	end
	return "Rock"
end

-- result: a RaycastResult
function Surface.Of(result)
	return Surface.Classify(result.Instance, result.Material)
end

return Surface
