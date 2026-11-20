-- tips.lua :: what the tooltips of game things say (public/js/tooltip.js, docs/APP.md
-- "Tooltips"). Each function takes a row (a spell, an item, a monster, a class: the
-- tables' columns, lore included; the fight menu's actions take their own arguments) and
-- returns the ctx of templates/tip/tip.html:
-- { title, meta = { short facts }, lines = { stat lines }, body = text, lore = text }.
-- Templates render them with the `tip(kind, row)` helper (lib/view.lua), which escapes
-- everything. Plain data: no HTML here.
local classes = require("lib.classes")
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

-- An item: its icon (when it has one) and name; its kind (and where a consumable works);
-- what equipping it does or a consumable's power, and the spell it casts with its charges
-- (extra.charges: this one's charges left); its description; its lore.
function tips.item(it, extra)
	local meta = { CATEGORY[it.category] or CATEGORY.misc }
	local lines
	if it.category == "consumable" then
		meta[#meta + 1] = USABLE[it.usable_in] or USABLE.fight
		lines = items.use_lines(it)
	else
		lines = type(it.modifiers) == "table" and items.attributes(it) or {}
	end
	for _, l in ipairs(items.charge_lines(it, extra and extra.charges)) do lines[#lines + 1] = l end
	return { title = it.name, icon = items.icon(it), meta = meta, lines = lines, body = it.description, lore = it.lore }
end

-- The fight menu's button of an equipped item that casts (entry: its user_items entry):
-- the item; the spell, its charges left and that it costs no MP; the item's description,
-- then the spell's; the item's lore.
function tips.gear(entry)
	local it = entry.item
	local spell = items.spell(it)
	local meta = { "Casts " .. (spell and spell.name or it.casts),
		"Charges " .. math.min(entry.charges, it.charges) .. "/" .. it.charges, "No MP" }
	local lines = spell and (spell.description or "") ~= "" and { spell.name .. ": " .. spell.description } or {}
	return { title = it.name, icon = items.icon(it), meta = meta, lines = lines, body = it.description, lore = it.lore }
end

-- A consumable's button in the fight menu (row: the items row, qty: how many in the bag).
function tips.consumable(it, qty)
	local t = tips.item(it)
	table.insert(t.meta, 2, "x" .. qty)
	return t
end

-- A monster: name; level; its description; its lore.
function tips.monster(m)
	return { title = m.name, meta = { "Level " .. m.level }, body = m.description, lore = m.lore }
end

-- The fight menu's Attack button: the player's attack power (and the weapon's name, when
-- one is equipped).
function tips.attack(power, weapon)
	local meta = { "Attack Power " .. power }
	if weapon then meta[#meta + 1] = weapon end
	return { title = "Attack", meta = meta, body = "Strike the monster with your weapon." }
end

-- The fight menu's Run button.
function tips.run()
	return { title = "Run", body = "Try to escape. The monster may block your way and strike." }
end

-- A class: name; starting HP and MP, and the spells it knows from the start; its description's points (one per line); its lore.
function tips.class(c)
	local lines = {}
	for line in (tostring(c.description or "") .. "\n"):gmatch("([^\n]*)\n") do
		local point = line:match("^%s*(.-)%s*$")
		if point ~= "" then lines[#lines + 1] = point end
	end
	local known = {}
	for _, s in ipairs(classes.start_spells(c)) do known[#known + 1] = s.name end
	local meta = { "Starts with " .. c.start_hp .. " HP, " .. c.start_mp .. " MP" }
	if #known > 0 then meta[#meta + 1] = "Knows " .. table.concat(known, ", ") end
	return {
		title = c.name,
		meta = meta,
		lines = lines,
		lore = c.lore,
	}
end

return tips
