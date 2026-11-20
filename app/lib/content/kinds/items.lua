-- content/kinds/items.lua :: items (app/content/items/<key>.lua) -> the items table. See
-- lib/content/schema.lua for the kind interface and docs/APP.md "Items" for the file format.
--
-- Gear (category weapon, armor, shield or accessory) is equipped in its slot and adds its
-- attack, defense and `modifiers` (stat bonuses, lib/stats.lua) while equipped; it never
-- stacks. Modifiers are stored as text (stats.encode_modifiers) in items.modifiers; the
-- flat form has them as "modifiers.1.stat", "modifiers.1.amount". Consumables stack up to
-- max_stack in the bag and are scripted like spells (docs/APP.md "Scripting spells and
-- items"): power, data and message strings are data, their use function (and the
-- optional can_use) stays in the file (lib/content/scripted.lua). Quest items can't be
-- sold or discarded and don't count against the bag size. Gear may cast a spell (casts: a
-- spell key usable in fights) with charges instead of MP (charges: when full; each
-- user_items row has its own). icon: a PNG in public/images/items/ (default: the spells'
-- default icon).
local scripted = require("lib.content.scripted")
local schema = require("lib.content.schema")
local stats = require("lib.stats")

local items = { name = "items", table = "items", dir = "content.items", label = "item" }

items.CATEGORIES = { "weapon", "armor", "shield", "accessory", "consumable", "quest", "misc" }
-- category -> equipment slot (nil: a bag item)
items.SLOT = { weapon = "weapon", armor = "armor", shield = "shield", accessory = "accessory" }

items.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page and in the bag." },
	schema.lore_field(),
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
	-- consumables
	{ name = "usable_in", type = "choice", values = { "town", "fight", "both" }, default = "fight", label = "Usable in" },
	{ name = "target", type = "choice", values = { "enemy", "self" }, default = "enemy", label = "Target" },
	{ name = "power", type = "int", default = 0, min = 0, max = 1000000, admin = true, label = "Power",
		help = "What the item's code makes of it: the HP it heals, ..." },
	-- gear that casts a spell
	{ name = "casts", type = "key", refs = "spells", default = "", label = "Casts",
		help = "The spell it casts in a fight while equipped (with charges instead of MP)." },
	{ name = "charges", type = "int", default = 0, min = 0, max = 1000, admin = true, label = "Charges",
		help = "Charges when full: one per cast; resting at an inn refills those of equipped items." },
	{ name = "icon", type = "icon", dir = "images/items", fallback = "images/skills/default.png", default = "",
		admin = true, label = "Icon",
		help = "A PNG in public/images/items/, without \".png\" (herb: herb.png); empty: the default icon." },
}

items.FUNCTIONS = { { "use", true }, { "can_use", false } }
items.extra_keys = scripted.extra_keys(items.FUNCTIONS, { modifiers = true })
-- fields only consumables have
local CONSUMABLE = { usable_in = true, target = true, power = true }

local by_name = {}
for _, f in ipairs(items.fields) do by_name[f.name] = f end

-- Modifier stats and amounts, the consumables' messages and numbers are overridable
-- (lib/content/scripted.lua); a modifier's kind is not. An override of a modifier index
-- the file doesn't have adds that modifier (with both its stat and amount).
function items.field(name)
	if by_name[name] then return by_name[name] end
	local i, param = tostring(name):match("^modifiers%.(%d+)%.([%a_]+)$")
	if i then
		if param == "stat" then
			return { name = name, type = "choice", values = stats.STATS, admin = true, label = "Modifier " .. i .. " stat" }
		elseif param == "amount" then
			return { name = name, type = "int", min = stats.AMOUNT.min, max = stats.AMOUNT.max, admin = true,
							 label = "Modifier " .. i .. " amount" }
		end
		return nil
	end
	return scripted.field(name)
end

local function modifier_list(data, flat, err)
	if data.modifiers == nil then return {} end
	local list, errs = stats.validate_modifiers(data.modifiers)
	if not list then
		for _, e in ipairs(errs) do err("modifiers" .. (e:sub(1, 1) == "[" and "" or " ") .. e) end
		return nil
	end
	for i, m in ipairs(list) do
		flat["modifiers." .. i .. ".stat"] = m.stat
		flat["modifiers." .. i .. ".amount"] = m.amount
	end
	return list
end

function items.validate_extra(data, flat, err)
	local slot = items.SLOT[flat.category]
	if flat.category and data.slot ~= nil and data.slot ~= slot then
		err("field 'slot' must be " .. (slot and ('"' .. slot .. '"') or "absent") .. " for category " ..
			flat.category .. " (or leave it out)")
	end
	flat.slot = slot
	local modifiers = modifier_list(data, flat, err)
	if data.sellable == nil then
		flat.sellable = ((flat.price or 0) > 0 and flat.category ~= "quest") and 1 or 0
	end
	if not flat.category then return end
	if flat.category == "consumable" then
		scripted.validate(data, flat, err, items.FUNCTIONS)
		if flat.usable_in ~= "fight" and flat.target == "enemy" then
			err("usable_in = \"" .. flat.usable_in .. "\" needs target = \"self\" (outside fights there is no " ..
				"enemy); use usable_in = \"fight\" for an item used on the enemy")
		end
	else
		local extra = {}
		for name in pairs(CONSUMABLE) do
			if data[name] ~= nil then extra[#extra + 1] = name end
		end
		if scripted.present(data, items.FUNCTIONS) then extra[#extra + 1] = "use/can_use/messages/data" end
		table.sort(extra)
		if #extra > 0 then
			err(table.concat(extra, ", ") .. ": for consumables, not " .. flat.category ..
				(slot and " (gear has attack, defense and modifiers)" or ""))
		end
	end
	if slot then
		if flat.max_stack ~= 1 then err("max_stack must be 1 for gear (" .. flat.category .. ")") end
	else
		if flat.attack ~= 0 or flat.defense ~= 0 then
			err("attack and defense are for gear (weapon, armor, shield, accessory), not " .. flat.category)
		end
		if modifiers and #modifiers > 0 then
			err("modifiers are for gear (weapon, armor, shield, accessory), not " .. flat.category)
		end
	end
	local casts, charges = flat.casts or "", flat.charges or 0
	if casts ~= "" and not slot then
		err("casts is for gear (weapon, armor, shield, accessory), not " .. flat.category)
	end
	if casts ~= "" and charges < 1 then err("casts needs charges (1 or more)") end
	if casts == "" and charges ~= 0 then err("charges are for items that cast a spell (casts = \"<spell key>\")") end
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

-- The spell it casts must be castable in fights (load.all, after the key was found to exist).
function items.validate_refs(flat, all, err)
	local spells = all.kinds.spells and all.kinds.spells.by_key or {}
	local spell = (flat.casts or "") ~= "" and spells[flat.casts]
	if spell and spell.usable_in == "town" then err(("casts: the spell '%s' can't be cast in fights"):format(flat.casts)) end
end

function items.write_children(id, flat)
	dk.db:exec("UPDATE items SET modifiers = ? WHERE id = ?", stats.encode_modifiers(items.modifiers(flat)), id)
	scripted.write("items", id, flat)
end

-- Admin page fields: name, description, price, the gear's attack/defense and modifiers,
-- the drop settings of items that drop, sellable, and the consumables' power, numbers and
-- messages.
function items.admin_fields(flat)
	local out = {}
	local gear = items.SLOT[flat.category] ~= nil
	local consumable = flat.category == "consumable"
	for _, f in ipairs(items.fields) do
		local show = f.admin
		if f.name == "attack" or f.name == "defense" then show = gear end
		if f.name == "drop_level" or f.name == "droppable" then show = flat.drop_level ~= nil end
		if f.name == "power" then show = consumable end
		if f.name == "charges" then show = (flat.casts or "") ~= "" end
		if show then out[#out + 1] = f end
	end
	for _, i in ipairs(modifier_indices(flat)) do
		out[#out + 1] = items.field("modifiers." .. i .. ".stat")
		out[#out + 1] = items.field("modifiers." .. i .. ".amount")
	end
	for _, f in ipairs(scripted.admin_fields(flat)) do out[#out + 1] = f end
	return out
end

return items
