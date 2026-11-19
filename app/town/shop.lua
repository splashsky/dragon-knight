-- town/shop.lua :: legacy towns.php buy() / buy2() / buy3(): weapons, armor and shields.
local common = require("town.common")
local php = require("lib.php")
local view = require("lib.view")

local shop = {}

-- items.type -> the users columns that slot uses.
local SLOTS = {
	[1] = { id = "weaponid", name = "weaponname", stat = "attackpower" },
	[2] = { id = "armorid",  name = "armorname",  stat = "defensepower" },
	[3] = { id = "shieldid", name = "shieldname", stat = "defensepower" },
}

-- users columns an item special ("column,value") may change, and whether the legacy
-- MySQL column was UNSIGNED. Legacy accepted any users column (admin help: "it is
-- suggested that you only use the ones from the list below"); anything not listed here
-- is ignored instead of being spliced into SQL.
local SPECIAL_COLUMNS = {
	maxhp = true, maxmp = true, maxtp = true, strength = true, dexterity = true,
	attackpower = true, defensepower = true, currenthp = true, currentmp = true,
	currenttp = true, gold = true, experience = true,
	goldbonus = false, expbonus = false,
}

local NO_ITEM = { attribute = 0, buycost = 0, special = "X" }

-- PHP's numeric value of a string in arithmetic ("50" -> 50, "-5" -> -5, "x" -> 0).
local function num(s)
	return tonumber(tostring(s or ""):match("^%s*([+-]?%d+%.?%d*)")) or 0
end

-- The item currently in the slot, or NO_ITEM when the slot is empty (or the item row was
-- deleted -- legacy produced a broken UPDATE in that case).
local function equipped(user, slot)
	local id = user[slot.id]
	if id == 0 then return NO_ITEM, false end
	local row = dk.db:first("SELECT * FROM items WHERE id = ?", id)
	if not row then return NO_ITEM, false end
	return row, true
end

function shop.sellback(item)
	return php.ceil(item.buycost / 2)
end

-- Shared buy2/buy3 checks. Returns item, slot, old item, has_old or nil, error response.
local function check(req, id)
	local user = req.user
	local town = common.town_here(req)
	if not town then return nil, common.cheat(req) end
	if not php.in_list(town.itemslist, id) then return nil, common.cheat(req) end
	local item = dk.db:first("SELECT * FROM items WHERE id = ?", id)
	local slot = item and SLOTS[item.type]
	if not slot then return nil, common.cheat(req) end
	-- the list never links an item you already own (legacy let a crafted URL buy it again)
	if user[slot.id] == item.id then return nil, common.cheat(req) end
	-- the old item is sold back in the same trade, so its value counts toward the price
	-- (legacy compared gold alone against the full price)
	local old, has_old = equipped(user, slot)
	if user.gold + shop.sellback(old) < item.buycost then
		return nil, common.message(req, "Buy Items", "shop_poor")
	end
	return item, slot, old, has_old
end

-- GET /shop
function shop.list(req)
	local user = req.user
	local town = common.town_here(req)
	if not town then return common.cheat(req) end
	local items = {}
	for _, it in ipairs(dk.db:query("SELECT * FROM items ORDER BY id")) do
		if php.in_list(town.itemslist, it.id) then
			items[#items + 1] = {
				item = it,
				owned = user.weaponid == it.id or user.armorid == it.id or user.shieldid == it.id,
				special = it.special ~= "X",
			}
		end
	end
	return view.page(req, "Buy Items", "town/shop", { items = items })
end

-- GET /shop/buy/#id
function shop.confirm(req, params)
	local item, slot, old, has_old = check(req, params.id)
	if not item then return slot end
	return view.page(req, "Buy Items", "town/shop_buy", {
		item = item, old = has_old and old or nil, sellback = shop.sellback(old),
	})
end

-- POST /shop/buy/#id
function shop.buy(req, params)
	if req.form.cancel ~= nil then return view.redirect("/") end
	local item, slot, old = check(req, params.id)
	if not item then return slot end
	local user = req.user

	local u, cols, seen = {}, {}, {}
	for k, v in pairs(user) do u[k] = v end
	local function touch(col)
		if not seen[col] then seen[col], cols[#cols + 1] = true, col end
	end
	local function special(code, sign)
		if code == "X" then return end
		local parts = php.explode(",", code)
		local col, value = parts[1], num(parts[2]) * sign
		if SPECIAL_COLUMNS[col] == nil then
			dk.log("warn", "item special ignored (column not allowed): " .. tostring(code))
			return
		end
		u[col] = u[col] + value
		touch(col)
		-- fixed: legacy only wrote the slot's own stat column, so e.g. a strength special on
		-- armor never reached attackpower.
		if col == "strength" then
			u.attackpower = u.attackpower + value
			touch("attackpower")
		end
		if col == "dexterity" then
			u.defensepower = u.defensepower + value
			touch("defensepower")
		end
	end
	special(item.special, 1)
	special(old.special, -1)

	u.gold = u.gold + shop.sellback(old) - item.buycost
	u[slot.stat] = u[slot.stat] + item.attribute - old.attribute
	u[slot.id] = item.id
	u[slot.name] = item.name
	if u.currenthp > u.maxhp then u.currenthp = u.maxhp end
	if u.currentmp > u.maxmp then u.currentmp = u.maxmp end
	if u.currenttp > u.maxtp then u.currenttp = u.maxtp end
	for _, col in ipairs({ "gold", slot.stat, slot.id, slot.name, "currenthp", "currentmp", "currenttp" }) do
		touch(col)
	end

	-- later assignments win in MySQL, so writing each column's final value is equivalent
	local sets, args = {}, {}
	for i, col in ipairs(cols) do
		local v = u[col]
		if type(v) == "number" then
			v = SPECIAL_COLUMNS[col] == false and php.mysql_int(v) or php.mysql_uint(v)
		end
		sets[i], args[i] = col .. " = ?", v
	end
	args[#args + 1] = user.id
	dk.db:exec("UPDATE users SET " .. table.concat(sets, ", ") .. " WHERE id = ?", table.unpack(args))
	return common.message(req, "Buy Items", "shop_done")
end

return shop
