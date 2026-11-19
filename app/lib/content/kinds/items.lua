-- content/kinds/items.lua :: items (app/content/items/<key>.lua) -> the items table. See
-- lib/content/schema.lua for the kind interface and docs/APP.md "Items" for the file format.
--
-- Gear (category weapon, armor, shield or accessory) is equipped in its slot and adds its
-- attack, defense and `modifiers` (stat effects, lib/effects.lua) while equipped; it never
-- stacks. Consumables stack up to max_stack in the bag and run their `use_effects` when
-- used. Quest items can't be sold or discarded and don't count against the bag size.
-- Modifiers and use effects are stored as text (effects.encode) in items.modifiers and
-- items.use_effects; the flat form has them as "modifiers.1.stat", "use_effects.1.amount".
local effects = require("lib.effects")

local items = {
	name = "items", table = "items", dir = "content.items", label = "item",
	extra_keys = { modifiers = true, use_effects = true },
}

items.CATEGORIES = { "weapon", "armor", "shield", "accessory", "consumable", "quest", "misc" }
-- category -> equipment slot (nil: a bag item)
items.SLOT = { weapon = "weapon", armor = "armor", shield = "shield", accessory = "accessory" }

items.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page and in the bag." },
	{ name = "category", type = "choice", values = items.CATEGORIES, required = true, label = "Category" },
	{ name = "slot", type = "choice", values = { "weapon", "armor", "shield", "accessory" }, label = "Slot" },
	{ name = "price", type = "int", default = 0, min = 0, max = 10000000, admin = true, label = "Price",
		help = "In gold. Shops buy items back for half (rounded up)." },
	{ name = "attack", type = "int", default = 0, min = -1000000, max = 1000000, admin = true,
		label = "Attack Power", help = "Added to attack power while equipped." },
	{ name = "defense", type = "int", default = 0, min = -1000000, max = 1000000, admin = true,
		label = "Defense Power", help = "Added to defense power while equipped." },
	{ name = "max_stack", type = "int", default = 1, min = 1, max = 1000, label = "Max stack" },
	{ name = "drop_level", type = "int", min = 1, max = 1000, admin = true, label = "Drop level",
		help = "Monsters of this level and up may drop it (1 in 30 victories without a level-up)." },
	{ name = "sellable", type = "bool", admin = true, label = "Sellable",
		help = "Shops buy it (default: when it has a price)." },
	{ name = "droppable", type = "bool", default = true, admin = true, label = "Droppable",
		help = "Monsters drop it (with a drop level)." },
}

local by_name = {}
for _, f in ipairs(items.fields) do by_name[f.name] = f end

-- Modifier stats and amounts and use effect parameters are overridable; kinds are not.
-- An override of a modifier index the file doesn't have adds that modifier (with both
-- its stat and amount).
function items.field(name)
	if by_name[name] then return by_name[name] end
	local i, param = tostring(name):match("^modifiers%.(%d+)%.([%a_]+)$")
	if i then
		if param == "stat" then
			return { name = name, type = "choice", values = effects.STATS, admin = true, label = "Modifier " .. i .. " stat" }
		elseif param == "amount" then
			local spec = effects.param_spec("amount", true)
			return { name = name, type = "int", min = spec.min, max = spec.max, admin = true,
							 label = "Modifier " .. i .. " amount" }
		end
		return nil
	end
	local j, p = tostring(name):match("^use_effects%.(%d+)%.([%a_]+)$")
	if not j or p == "kind" then return nil end
	local spec = effects.param_spec(p)
	if not spec then return nil end
	return { name = name, type = spec.type, min = spec.min, max = spec.max, admin = true,
					 label = "Use effect " .. j .. " " .. spec.label }
end

local function effect_list(data, field, passive, flat, err)
	if data[field] == nil then return {} end
	local list, errs = effects.validate(data[field], passive)
	if not list then
		for _, e in ipairs(errs) do err(field .. (e:sub(1, 1) == "[" and "" or " ") .. e) end
		return nil
	end
	effects.flatten(list, field, flat)
	return list
end

function items.validate_extra(data, flat, err)
	local slot = items.SLOT[flat.category]
	if flat.category and data.slot ~= nil and data.slot ~= slot then
		err("field 'slot' must be " .. (slot and ('"' .. slot .. '"') or "absent") .. " for category " ..
			flat.category .. " (or leave it out)")
	end
	flat.slot = slot
	local modifiers = effect_list(data, "modifiers", true, flat, err)
	local use = effect_list(data, "use_effects", false, flat, err)
	if data.sellable == nil then
		flat.sellable = ((flat.price or 0) > 0 and flat.category ~= "quest") and 1 or 0
	end
	if not flat.category then return end
	if slot then
		if flat.max_stack ~= 1 then err("max_stack must be 1 for gear (" .. flat.category .. ")") end
		if use and #use > 0 then err("use_effects are for consumables; gear has modifiers") end
	else
		if flat.attack ~= 0 or flat.defense ~= 0 then
			err("attack and defense are for gear (weapon, armor, shield, accessory), not " .. flat.category)
		end
		if modifiers and #modifiers > 0 then
			err("modifiers are for gear (weapon, armor, shield, accessory), not " .. flat.category)
		end
	end
	if flat.category == "consumable" then
		if use and #use == 0 then err("missing field 'use_effects' (a consumable must do something)") end
	elseif use and #use > 0 and slot == nil then
		err("use_effects are for consumables, not " .. flat.category)
	end
	if flat.category == "quest" and flat.sellable == 1 then err("quest items can't be sellable") end
	if flat.sellable == 1 and flat.price == 0 then err("sellable = true needs a price") end
end

-- Indices of the modifiers of a flat entity, in order: those with a stat (the file's, and
-- any an override added; see items.field).
local function modifier_indices(flat)
	local out = {}
	for k in pairs(flat) do
		local i = k:match("^modifiers%.(%d+)%.stat$")
		if i then out[#out + 1] = math.tointeger(tonumber(i)) end
	end
	table.sort(out)
	return out
end

-- The modifiers of a flat entity (an index needs both its stat and its amount).
function items.modifiers(flat)
	local list = {}
	for _, i in ipairs(modifier_indices(flat)) do
		local amount = flat["modifiers." .. i .. ".amount"]
		if amount ~= nil then
			list[#list + 1] = { kind = "stat", stat = flat["modifiers." .. i .. ".stat"], amount = amount }
		end
	end
	return list
end

function items.use_effects(flat)
	return effects.unflatten(flat, "use_effects")
end

function items.write_children(id, flat)
	dk.db:exec("UPDATE items SET modifiers = ?, use_effects = ? WHERE id = ?",
						 effects.encode(items.modifiers(flat)), effects.encode(items.use_effects(flat)), id)
end

-- Admin page fields: name, description, price, the gear's attack/defense and modifiers,
-- the drop settings of items that drop, sellable, and the use effects' parameters.
function items.admin_fields(flat)
	local out = {}
	local gear = items.SLOT[flat.category] ~= nil
	for _, f in ipairs(items.fields) do
		local show = f.admin
		if f.name == "attack" or f.name == "defense" then show = gear end
		if f.name == "drop_level" or f.name == "droppable" then show = flat.drop_level ~= nil end
		if show then out[#out + 1] = f end
	end
	for _, i in ipairs(modifier_indices(flat)) do
		out[#out + 1] = items.field("modifiers." .. i .. ".stat")
		out[#out + 1] = items.field("modifiers." .. i .. ".amount")
	end
	for i, e in ipairs(items.use_effects(flat)) do
		for _, p in ipairs(effects.KINDS[e.kind] and effects.KINDS[e.kind].params or {}) do
			if e[p] ~= nil then
				local spec = items.field("use_effects." .. i .. "." .. p)
				spec.label = "Use effect " .. i .. " (" .. effects.label(e) .. "): " .. effects.param_spec(p).label
				out[#out + 1] = spec
			end
		end
	end
	return out
end

return items
