-- tips.lua :: what the tooltips of game things say (public/js/tooltip.js, docs/APP.md
-- "Tooltips"). Each function takes a row (a spell, an item, a monster, a class: the
-- tables' columns, lore included; the fight menu's actions take their own arguments) and
-- returns the ctx of templates/tip/tip.html:
-- { title, meta = { short facts }, lines = { stat lines }, body = text, lore = text }.
-- Templates render them with the `tip(kind, row)` helper (lib/view.lua), which escapes
-- everything. Plain data: no HTML here.
local classes = require("lib.classes")
local elements = require("lib.elements")
local fields = require("lib.fields")
local items = require("lib.items")
local php = require("lib.php")
local schema = require("lib.content.schema")

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

local CATEGORY = items.CATEGORY_LABELS

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
-- the item; the spell, its charges left ("3/5 Charges"), that it costs no MP and, for one
-- that isn't rechargeable, "Single use"; the item's description, then the spell's; the
-- item's lore.
function tips.gear(entry)
	local it = entry.item
	local spell = items.spell(it)
	local meta = { "Casts " .. (spell and spell.name or it.casts),
		math.min(entry.charges, it.charges) .. "/" .. it.charges .. (it.charges == 1 and " Charge" or " Charges"), "No MP" }
	if not items.rechargeable(it) then meta[#meta + 1] = "Single use" end
	local lines = spell and (spell.description or "") ~= "" and { spell.name .. ": " .. spell.description } or {}
	return { title = it.name, icon = items.icon(it), meta = meta, lines = lines, body = it.description, lore = it.lore }
end

-- A consumable's button in the fight menu (row: the items row, qty: how many in the bag).
function tips.consumable(it, qty)
	local t = tips.item(it)
	table.insert(t.meta, 2, "x" .. qty)
	return t
end

-- The rows of templates/tip/shop.html's stats table: { label, value, delta, better }; with
-- `old` (the item worn in that slot), every stat either has, the change if one replaces
-- the other ("—": the new one hasn't it; "+0" with `better` nil: no change).
local function stat_rows(it, old)
	local rows = {}
	for _, c in ipairs(items.compare(it, old)) do
		local r = { label = c.label, value = c.new and items.signed(c.stat, c.new) or "—" }
		if old then
			r.delta = items.signed(c.stat, c.delta)
			if c.delta ~= 0 then r.better = c.delta > 0 end
		end
		rows[#rows + 1] = r
	end
	return rows
end

-- What it does besides its stats: a weapon's element, the resistances and wards gear
-- gives, a consumable's description (its effect), the spell gear casts and its charges.
local function effects(it, charges)
	local out = items.affinity_lines(it)
	if it.category == "consumable" and (it.description or "") ~= "" then out[#out + 1] = it.description end
	for _, l in ipairs(items.charge_lines(it, charges)) do out[#out + 1] = l end
	return out
end

local function kind_line(it)
	local kind = CATEGORY[it.category] or CATEGORY.misc
	if it.category == "consumable" then return kind .. " · " .. (USABLE[it.usable_in] or USABLE.fight) end
	if items.is_gear(it) and it.slot ~= "accessory" then return kind end   -- worn or into the bag: the player's choice
	return kind .. " · goes into your bag"
end

-- An item for sale (the shop's buttons; templates/tip/shop.html): name, picture and kind;
-- the price and the player's gold (what is missing, when it is short); the stats, compared
-- with what is worn in its slot; its effects; what the worn item sells back for;
-- its description (a consumable's is its effect). o: { gold, old (the equipped entry it
-- replaces), sellback (what that sells back for, 0: nothing), short }.
function tips.shop(it, o)
	local old = o.old and o.old.item
	local t = { title = it.name, icon = items.icon(it), kind = kind_line(it), price_label = "Price", price = it.price,
		stats = stat_rows(it, old), compare = old and old.name, effects = effects(it) }
	if o.short then
		t.note, t.short = "You need " .. php.number_format(it.price - o.gold - (o.sellback or 0)) .. " more gold", true
	else
		t.note = "You have " .. php.number_format(o.gold) .. " gold"
	end
	if old and (o.sellback or 0) > 0 then
		t.replaces = "Your " .. old.name .. " sells back for " .. php.number_format(o.sellback) .. " gold"
	end
	if it.category ~= "consumable" then t.body = it.description end
	return t
end

-- A bag entry the shop buys (the Sell buttons; templates/tip/shop.html): what the shop pays
-- (each, and for the whole stack), the item's stats and effects, its description.
function tips.sell(entry, price)
	local it = entry.item
	local t = { title = it.name, icon = items.icon(it), kind = kind_line(it):gsub(" · .*", ""), price_label = "Sells for",
		price = price, each = entry.qty > 1, stats = stat_rows(it), effects = effects(it, entry.charges) }
	if entry.qty > 1 then t.note = "You have " .. entry.qty .. ": " .. php.number_format(entry.qty * price) .. " gold for all" end
	if it.category ~= "consumable" then t.body = it.description end
	return t
end

-- A monster: its portrait (when it has one) and name; level; its resistances, weaknesses
-- and wards; its description; its lore.
function tips.monster(m)
	return { title = m.name, icon = schema.entity_icon("monsters", m.icon), meta = { "Level " .. m.level },
		lines = elements.lines(m.resist, m.ward), body = m.description, lore = m.lore }
end

-- A field on the battlefield: its icon (when it has one) and name; its group (and, a
-- spell's, the time it has left: "30s"); what it does ("Fire damage -40%", "Burning can't
-- take hold", "Dexterity -20%"); its description; its lore.
function tips.field(f, left)
	local meta = { fields.GROUP_NAMES[f.group] or f.group }
	if left then meta[#meta + 1] = left .. " left" end
	return { title = f.name, icon = schema.entity_icon("fields", f.icon), meta = meta, lines = fields.lines(f),
		body = f.description, lore = f.lore }
end

-- The fight menu's Attack button: the player's attack power (and the weapon's name, when
-- one is equipped).
function tips.attack(power, weapon)
	local meta = { "Attack Power " .. power }
	if weapon then meta[#meta + 1] = weapon end
	return { title = "Attack", meta = meta, body = "Strike the monster with your weapon." }
end

-- The fight menu's Guard button.
function tips.guard()
	return { title = "Guard", body = "Raise your guard: take less damage from the monster's attacks until your next turn. " ..
		"A turn that runs out is a guard too." }
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
