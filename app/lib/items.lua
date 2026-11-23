-- items.lua :: items as the game uses them (rows of the items table, synced from
-- app/content/items/*.lua; see lib/content/), what towns sell (town_items) and how items
-- are described. Rows come back with `modifiers` decoded into a list (lib/stats.lua) and
-- `messages` and `data` into tables (lib/content/scripted.lua); what a consumable does is
-- its file's use (lib/action.lua).
local cache = require("lib.cache")
local elements = require("lib.elements")
local kind = require("lib.content.kinds.items")
local php = require("lib.php")
local schema = require("lib.content.schema")
local scripted = require("lib.content.scripted")
local spells = require("lib.spells")
local stats = require("lib.stats")

local items = {}

items.CATEGORIES = kind.CATEGORIES
items.SLOT = kind.SLOT

-- category -> heading (help and admin pages)
items.HEADINGS = {
	weapon = "Weapons", armor = "Armor", shield = "Shields", accessory = "Accessories",
	consumable = "Consumables", quest = "Quest Items", misc = "Other Items",
}

-- stat -> display name (modifiers)
items.STAT_LABELS = {
	maxhp = "Max HP", maxmp = "Max MP", maxtp = "Max TP", strength = "Strength", dexterity = "Dexterity",
	attack = "Attack Power", defense = "Defense Power", exp_bonus_pct = "Experience Bonus",
	gold_bonus_pct = "Gold Bonus",
}

-- An item's kind as the pages say it (its category).
items.CATEGORY_LABELS = {
	weapon = "Weapon", armor = "Armor", shield = "Shield", accessory = "Accessory", consumable = "Consumable",
	quest = "Quest item", misc = "Item",
}

function items.category_label(item)
	return items.CATEGORY_LABELS[item.category] or items.CATEGORY_LABELS.misc
end

function items.decode(row)
	if row then
		row.modifiers = stats.decode_modifiers(row.modifiers)
		row.messages = scripted.decode_messages(row.messages)
		row.data = scripted.decode_data(row.data)
	end
	return row
end

-- the rows by id and key, kept for the request as they are used (lib/cache.lua): each lookup
-- a copy of the row (its decoded tables shared)
local rows = cache.rows("items", items.decode, { copy = true })

local function decode_all(list)
	for _, r in ipairs(list) do rows.remember(r) end
	return list
end

-- The item with id `id` (retired or not), or nil.
function items.get(id)
	return rows.get(id)
end

-- The items of a list of ids (or keys, by = "key"), read in one query at most: { [id] = row }.
function items.many(list, by)
	return rows.many(list, by)
end

function items.by_key(key)
	return rows.by_key(key)
end

-- Items that aren't retired (help pages) / every item (admin), by id.
function items.active()
	return decode_all(dk.db:query("SELECT * FROM items WHERE retired = 0 ORDER BY id"))
end

function items.all()
	return decode_all(dk.db:query("SELECT * FROM items ORDER BY id"))
end

-- The (not retired) items town `town_id` sells, by id. Shop lists name items by key
-- (town_items.item_key): one the content doesn't have (yet) isn't sold.
function items.town(town_id)
	return decode_all(dk.db:query("SELECT i.* FROM town_items t JOIN items i ON i.key = t.item_key " ..
																"WHERE t.town_id = ? AND i.retired = 0 ORDER BY i.id", town_id))
end

function items.sold_in(town_id, item_id)
	return dk.db:value("SELECT 1 FROM town_items t JOIN items i ON i.key = t.item_key " ..
										 "WHERE t.town_id = ? AND i.id = ? AND i.retired = 0", town_id, item_id) ~= nil
end

-- Makes town `town_id` sell exactly the items `keys` (admin town editor).
function items.set_town(town_id, keys)
	dk.db:exec("DELETE FROM town_items WHERE town_id = ?", town_id)
	for _, key in ipairs(keys) do
		dk.db:exec("INSERT OR IGNORE INTO town_items (town_id, item_key) VALUES (?, ?)", town_id, key)
	end
end

-- The item keys of a town's shop list (retired and unknown ones too), by item id, unknown
-- keys last.
function items.town_keys(town_id)
	local keys = {}
	for _, r in ipairs(dk.db:query("SELECT t.item_key FROM town_items t LEFT JOIN items i ON i.key = t.item_key " ..
																 "WHERE t.town_id = ? ORDER BY i.id IS NULL, i.id, t.item_key", town_id)) do
		keys[#keys + 1] = r.item_key
	end
	return keys
end

-- Gear is equipped (in its slot); everything else lives in the bag.
function items.is_gear(item)
	return item.slot ~= nil
end

-- What a shop pays for it (the original's sell-back: half the price, rounded up).
function items.sell_price(item)
	return php.ceil(item.price / 2)
end

function items.can_sell(item)
	return item.sellable ~= 0 and item.category ~= "quest"
end

-- Whether a bag item can be used in `place` ("town" or "fight"): consumables, per their
-- usable_in. A retired one (its file is gone, and with it what it does) can't be used.
function items.usable(item, place)
	if item.category ~= "consumable" or (item.retired or 0) ~= 0 then return false end
	return item.usable_in == "both" or item.usable_in == place
end

-- The URL of the item's icon (its `icon` column: public/images/items/<icon>.png), or nil
-- when it has none or the file is missing (pages then draw what they did before icons).
function items.icon(item)
	local spec = kind.field("icon")
	if schema.has_icon(spec, item.icon) then return schema.icon_url(spec, item.icon) end
	return nil
end

-- The URL of the item's icon, or of the default icon (images/skills/default.png): icon
-- buttons and the bag grid.
function items.icon_url(item)
	return schema.icon_url(kind.field("icon"), item.icon)
end

-- Gear that casts a spell (casts, with charges instead of MP).
function items.casts(item)
	return (item.casts or "") ~= "" and (item.charges or 0) > 0
end

local cast_spells = {}   -- spell key -> spells row (this request)

-- The spell a casting item casts (a spells row, retired or not), or nil.
function items.spell(item)
	if not items.casts(item) then return nil end
	local key = item.casts
	if cast_spells[key] == nil then cast_spells[key] = spells.by_key(key) or false end
	return cast_spells[key] or nil
end

-- A casting item's lines: { "Casts Magic Bolt", "3/5 Charges" } (with `charges`, one
-- item's charges left; without, the full count: "5 Charges", "1 Charge"), then "Single
-- use" for one that isn't rechargeable (used up with its last charge).
function items.charge_lines(item, charges)
	if not items.casts(item) then return {} end
	local spell = items.spell(item)
	local max = item.charges
	local out = {
		"Casts " .. (spell and spell.name or item.casts),
		(charges and (math.min(charges, max) .. "/" .. max) or max) .. (max == 1 and " Charge" or " Charges"),
	}
	if not items.rechargeable(item) then out[#out + 1] = "Single use" end
	return out
end

-- Whether resting at an inn refills its charges (else it is used up with its last one).
function items.rechargeable(item)
	return item.rechargeable ~= 0 and item.rechargeable ~= false
end

-- A stat's amount as shown: "+5", "-3", "+10%" (the bonuses are percentages).
function items.signed(stat, n)
	local pct = stat == "exp_bonus_pct" or stat == "gold_bonus_pct"
	return (n >= 0 and "+" or "") .. n .. (pct and "%" or "")
end

-- What a piece of gear gives, in order: { { stat, amount }, ... } (attack, defense, then
-- its stat modifiers).
local function stat_amounts(it)
	local out = {}
	if (it.attack or 0) ~= 0 then out[#out + 1] = { "attack", it.attack } end
	if (it.defense or 0) ~= 0 then out[#out + 1] = { "defense", it.defense } end
	for _, m in ipairs(type(it.modifiers) == "table" and it.modifiers or {}) do
		if m.kind == "stat" then out[#out + 1] = { m.stat, m.amount } end
	end
	return out
end

-- Wearing `it` instead of `old` (nil: nothing), stat by stat: { stat, label, new, old,
-- delta } (the amounts; new or old nil where that item hasn't the stat; delta = new - old),
-- its own stats first, then those only `old` has.
function items.compare(it, old)
	local rows, olds, seen = {}, {}, {}
	local old_list = old and stat_amounts(old) or {}
	for _, a in ipairs(old_list) do olds[a[1]] = a[2] end
	for _, a in ipairs(stat_amounts(it)) do
		seen[a[1]] = true
		rows[#rows + 1] = { stat = a[1], label = items.STAT_LABELS[a[1]] or a[1], new = a[2], old = olds[a[1]],
			delta = a[2] - (olds[a[1]] or 0) }
	end
	for _, a in ipairs(old_list) do
		if not seen[a[1]] then
			rows[#rows + 1] = { stat = a[1], label = items.STAT_LABELS[a[1]] or a[1], old = a[2], delta = -a[2] }
		end
	end
	return rows
end

-- items.compare as the purchase and the drop card show it: { label, new, old (as text, "—"
-- when the item has none), delta (text, nil when 0), better }.
function items.compare_view(it, old)
	local out = {}
	for _, c in ipairs(items.compare(it, old)) do
		out[#out + 1] = { label = c.label, new = c.new and items.signed(c.stat, c.new) or "—",
			old = c.old and items.signed(c.stat, c.old) or "—",
			delta = c.delta ~= 0 and items.signed(c.stat, c.delta) or nil, better = c.delta > 0 }
	end
	return out
end

-- "Max HP +10", "Gold Bonus +10%", "Strength -5".
function items.stat_line(stat, amount)
	return (items.STAT_LABELS[stat] or stat) .. " " .. items.signed(stat, amount)
end

-- A weapon's element and the resistances and wards it gives: "Deals Fire damage", "Fire
-- Resistance +25%", "Sleep Ward +25%".
function items.affinity_lines(item)
	local out = {}
	if (item.element or "neutral") ~= "neutral" then out[#out + 1] = "Deals " .. elements.name(item.element) .. " damage" end
	for _, m in ipairs(type(item.modifiers) == "table" and item.modifiers or {}) do
		if m.kind == "resist" then
			out[#out + 1] = elements.name(m.element) .. " Resistance " .. items.signed("resist", m.amount) .. "%"
		elseif m.kind == "ward" then
			out[#out + 1] = elements.ward_name(m.status) .. " Ward " .. items.signed("ward", m.amount) .. "%"
		end
	end
	return out
end

-- What equipping it does: attack and defense, then the modifiers, as stat lines, then its
-- element, resistances and wards.
function items.attributes(item)
	local out = {}
	if item.attack ~= 0 then out[#out + 1] = items.stat_line("attack", item.attack) end
	if item.defense ~= 0 then out[#out + 1] = items.stat_line("defense", item.defense) end
	for _, l in ipairs(items.special_lines(item)) do out[#out + 1] = l end
	return out
end

-- The modifiers alone ("Strength +50", "Fire Resistance +25%") and a weapon's element, for
-- the shop's and help pages' Special column.
function items.special_lines(item)
	local out = {}
	for _, m in ipairs(item.modifiers) do
		if m.kind == "stat" then out[#out + 1] = items.stat_line(m.stat, m.amount) end
	end
	for _, l in ipairs(items.affinity_lines(item)) do out[#out + 1] = l end
	return out
end

-- A consumable's power, as a display line: { "Power 30" } (none when it has no power).
function items.use_lines(item)
	if item.category ~= "consumable" or (item.power or 0) == 0 then return {} end
	return { "Power " .. item.power }
end

return items
