-- items.lua :: items as the game uses them (rows of the items table, synced from
-- app/content/items/*.lua; see lib/content/), what towns sell (town_items) and how items
-- are described. Rows come back with `modifiers` and `use_effects` decoded into lists
-- (lib/effects.lua).
local effects = require("lib.effects")
local kind = require("lib.content.kinds.items")
local php = require("lib.php")

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

function items.decode(row)
	if row then
		row.modifiers = effects.decode(row.modifiers)
		row.use_effects = effects.decode(row.use_effects)
	end
	return row
end

local function decode_all(rows)
	for _, r in ipairs(rows) do items.decode(r) end
	return rows
end

-- The item with id `id` (retired or not), or nil.
function items.get(id)
	return items.decode(dk.db:first("SELECT * FROM items WHERE id = ?", id))
end

function items.by_key(key)
	return items.decode(dk.db:first("SELECT * FROM items WHERE key = ?", key))
end

-- Items that aren't retired (help pages) / every item (admin), by id.
function items.active()
	return decode_all(dk.db:query("SELECT * FROM items WHERE retired = 0 ORDER BY id"))
end

function items.all()
	return decode_all(dk.db:query("SELECT * FROM items ORDER BY id"))
end

-- The (not retired) items town `town_id` sells, by id.
function items.town(town_id)
	return decode_all(dk.db:query("SELECT i.* FROM town_items t JOIN items i ON i.id = t.item_id " ..
																"WHERE t.town_id = ? AND i.retired = 0 ORDER BY i.id", town_id))
end

function items.sold_in(town_id, item_id)
	return dk.db:value("SELECT 1 FROM town_items t JOIN items i ON i.id = t.item_id " ..
										 "WHERE t.town_id = ? AND t.item_id = ? AND i.retired = 0", town_id, item_id) ~= nil
end

-- Makes town `town_id` sell exactly `ids` (admin town editor).
function items.set_town(town_id, ids)
	dk.db:exec("DELETE FROM town_items WHERE town_id = ?", town_id)
	for _, id in ipairs(ids) do
		dk.db:exec("INSERT OR IGNORE INTO town_items (town_id, item_id) VALUES (?, ?)", town_id, id)
	end
end

-- Item keys of a town's shop, by id (retired ones too).
function items.town_keys(town_id)
	local keys = {}
	for _, r in ipairs(dk.db:query("SELECT i.key FROM town_items t JOIN items i ON i.id = t.item_id " ..
																 "WHERE t.town_id = ? ORDER BY i.id", town_id)) do
		keys[#keys + 1] = r.key
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

-- Whether a bag item can be used in `place` ("town" or "fight"): consumables with use
-- effects; in town only when every effect works outside fights (heals).
function items.usable(item, place)
	if item.category ~= "consumable" or #item.use_effects == 0 then return false end
	return place == "fight" or effects.town_usable(item.use_effects)
end

-- "Max HP +10", "Gold Bonus +10%", "Strength -5".
function items.stat_line(stat, amount)
	local pct = stat == "exp_bonus_pct" or stat == "gold_bonus_pct"
	return (items.STAT_LABELS[stat] or stat) .. " " .. (amount >= 0 and "+" or "") .. amount .. (pct and "%" or "")
end

-- What equipping it does: attack and defense, then the modifiers, as stat lines.
function items.attributes(item)
	local out = {}
	if item.attack ~= 0 then out[#out + 1] = items.stat_line("attack", item.attack) end
	if item.defense ~= 0 then out[#out + 1] = items.stat_line("defense", item.defense) end
	for _, m in ipairs(item.modifiers) do
		if m.kind == "stat" then out[#out + 1] = items.stat_line(m.stat, m.amount) end
	end
	return out
end

-- The modifiers alone ("Strength +50"), for the shop's and help pages' Special column.
function items.special_lines(item)
	local out = {}
	for _, m in ipairs(item.modifiers) do
		if m.kind == "stat" then out[#out + 1] = items.stat_line(m.stat, m.amount) end
	end
	return out
end

-- What using it does: "Heal 30", "Heal MP 30".
function items.effect_lines(item)
	local out = {}
	for _, e in ipairs(item.use_effects) do out[#out + 1] = effects.label(e) .. " " .. effects.attribute(e) end
	return out
end

return items
