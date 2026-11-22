-- elements.lua :: typed damage, resistances and wards (docs/APP.md "Elements and wards").
-- Pure: no DB, no dice. lib/action.lua (the handles' :hurt, :resist, :ward) and fight/*
-- (attacks) use it, the pages to show what a monster or a piece of gear resists.
--
-- Every hit has an element (neutral unless it says otherwise). A combatant's resistance to
-- an element is a percent summed from its sources (its file, its gear, its statuses) and
-- clamped to -100..200: below 0 a weakness, 100 immunity, above 100 it absorbs (the excess
-- heals it). A ward is a percent chance, 0..100, that a status doesn't take hold.
local elements = {}

-- The elements, in the order the pages list them.
elements.LIST = {
	{ key = "neutral", name = "Physical", noun = "physical harm" },
	{ key = "fire", name = "Fire", noun = "fire" },
	{ key = "frost", name = "Frost", noun = "frost" },
	{ key = "lightning", name = "Lightning", noun = "lightning" },
	{ key = "water", name = "Water", noun = "water" },
	{ key = "wind", name = "Wind", noun = "wind" },
	{ key = "earth", name = "Earth", noun = "earth" },
	{ key = "holy", name = "Holy", noun = "holy light" },
	{ key = "shadow", name = "Shadow", noun = "shadow" },
	{ key = "arcane", name = "Arcane", noun = "arcane force" },
	{ key = "poison", name = "Poison", noun = "poison" },
}
elements.KEYS = {}
local BY_KEY = {}
for i, e in ipairs(elements.LIST) do
	elements.KEYS[i] = e.key
	BY_KEY[e.key] = e
end

elements.RESIST = { min = -100, max = 200 }
elements.WARD = { min = 0, max = 100 }

function elements.valid(key)
	return BY_KEY[key] ~= nil
end

-- "Fire" (the display name of an element key).
function elements.name(key)
	return BY_KEY[key].name
end

local function clamp(n, range)
	return math.max(range.min, math.min(range.max, n))
end

-- A summed resistance as it counts (-100..200).
function elements.clamp_resist(n)
	return clamp(n, elements.RESIST)
end

-- A summed ward as it counts (0..100).
function elements.clamp_ward(n)
	return clamp(n, elements.WARD)
end

-- The damage formula, the only one (attacks, spells and status ticks): n damage of an
-- element, scaled by the battlefield's percent for it (field_pct; 0 without fields), then
-- by the target's resistance (clamped). Returns what it deals and what it heals (an
-- absorbing target: it deals 0). A hit that dealt at least 1 before resistance and isn't
-- resisted fully deals at least 1. With field_pct 0 and resist 0 it deals n.
function elements.damage(n, field_pct, resist)
	resist = elements.clamp_resist(resist)
	local scaled = math.max(0, (n * (100 + field_pct)) // 100)
	if resist > 100 then return 0, (scaled * (resist - 100)) // 100 end
	if resist == 100 then return 0, 0 end
	local dealt = (scaled * (100 - resist)) // 100
	if dealt < 1 and scaled >= 1 then dealt = 1 end
	return dealt, 0
end

-- The line said after a hit against a weakness or a resistance ("It is weak to fire!",
-- "It resists frost.", "It is immune to arcane force.", "It absorbs the lightning!"; `you`:
-- the player is hit), or nil (resist 0).
function elements.note(element, resist, you)
	resist = elements.clamp_resist(resist)
	if resist == 0 then return nil end
	local noun = BY_KEY[element].noun
	local who = you and "You" or "It"
	if resist < 0 then return ("%s %s weak to %s!"):format(who, you and "are" or "is", noun) end
	if resist < 100 then return ("%s %s %s."):format(who, you and "resist" or "resists", noun) end
	if resist == 100 then return ("%s %s immune to %s."):format(who, you and "are" or "is", noun) end
	return ("%s %s the %s!"):format(who, you and "absorb" or "absorbs", noun)
end

-- "Sleep" (the name a ward goes by: its status key in words, "uber_damage": "Uber Damage").
function elements.ward_name(key)
	return (key:gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

-- What a resistance table and a ward table mean, as lines for the pages, elements in LIST
-- order then wards by key: "Weak to Frost (+50%)", "Resists Fire (50%)", "Immune to Arcane",
-- "Absorbs Lightning (50%)", "Wards off Sleep (100%)". Values are clamped; zeros say nothing.
function elements.lines(resist, ward)
	local out = {}
	for _, e in ipairs(elements.LIST) do
		local r = elements.clamp_resist((resist or {})[e.key] or 0)
		if r < 0 then out[#out + 1] = ("Weak to %s (+%d%%)"):format(e.name, -r)
		elseif r > 0 and r < 100 then out[#out + 1] = ("Resists %s (%d%%)"):format(e.name, r)
		elseif r == 100 then out[#out + 1] = "Immune to " .. e.name
		elseif r > 100 then out[#out + 1] = ("Absorbs %s (%d%%)"):format(e.name, r - 100) end
	end
	ward = ward or {}
	for _, key in ipairs(sorted_keys(ward)) do
		local w = elements.clamp_ward(ward[key])
		if w > 0 then out[#out + 1] = ("Wards off %s (%d%%)"):format(elements.ward_name(key), w) end
	end
	return out
end

-- The sum of tables of percents ({ fire = 50 }, { fire = -25, frost = 10 }: { fire = 25,
-- frost = 10 }); nil arguments count as empty.
function elements.sum(...)
	local out = {}
	for i = 1, select("#", ...) do
		for k, n in pairs(select(i, ...) or {}) do out[k] = (out[k] or 0) + n end
	end
	return out
end

return elements
