-- tips.lua :: what the tooltips of game things say (public/js/tooltip.js, docs/APP.md
-- "Tooltips"). Each function takes a row (a spell, an item, a monster, a class: the
-- tables' columns, lore included) and returns the ctx of templates/tip/tip.html:
-- { title, meta = { short facts }, lines = { stat lines }, body = text, lore = text }.
-- Templates render them with the `tip(kind, row)` helper (lib/view.lua), which escapes
-- everything. Plain data: no HTML here.
local items = require("lib.items")

local tips = {}

local USABLE = { fight = "In fights", town = "Outside fights", both = "In fights and in town" }

-- A spell: name; MP cost and where it can be cast; its description; its lore.
function tips.spell(s)
	return {
		title = s.name,
		meta = { s.mp .. " MP", USABLE[s.usable_in] or USABLE.fight },
		body = s.description,
		lore = s.lore,
	}
end

local CATEGORY = {
	weapon = "Weapon", armor = "Armor", shield = "Shield", accessory = "Accessory", consumable = "Consumable",
	quest = "Quest item", misc = "Item",
}

-- An item: name; its kind (and where a consumable works); what equipping it does or a
-- consumable's power; its description; its lore.
function tips.item(it)
	local meta = { CATEGORY[it.category] or CATEGORY.misc }
	local lines
	if it.category == "consumable" then
		meta[#meta + 1] = USABLE[it.usable_in] or USABLE.fight
		lines = items.use_lines(it)
	else
		lines = type(it.modifiers) == "table" and items.attributes(it) or {}
	end
	return { title = it.name, meta = meta, lines = lines, body = it.description, lore = it.lore }
end

-- A monster: name; level; its description; its lore.
function tips.monster(m)
	return { title = m.name, meta = { "Level " .. m.level }, body = m.description, lore = m.lore }
end

-- A class: name; starting HP and MP; its description's points (one per line); its lore.
function tips.class(c)
	local lines = {}
	for line in (tostring(c.description or "") .. "\n"):gmatch("([^\n]*)\n") do
		local point = line:match("^%s*(.-)%s*$")
		if point ~= "" then lines[#lines + 1] = point end
	end
	return {
		title = c.name,
		meta = { "Starts with " .. c.start_hp .. " HP, " .. c.start_mp .. " MP" },
		lines = lines,
		lore = c.lore,
	}
end

return tips
