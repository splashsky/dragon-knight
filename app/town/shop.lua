-- town/shop.lua :: legacy towns.php buy() / buy2() / buy3(), with the bag: the town's
-- items (town_items) and selling bag items back.
--   GET  /shop               the town's items + the Sell section (sellable bag items)
--   GET  /shop/buy/#id       confirmation; POST: gear in a slot that holds something:
--                            "keep" (the old item goes into the bag: needs a free slot) or
--                            "sell" (the old item is sold back, its value counts toward the
--                            price); otherwise "submit" (bag items: qty)
--   POST /shop/sell/#id      a bag entry (qty for stacks), for items.sell_price each
-- Weapons, armor and shields are equipped when bought; everything else (consumables,
-- accessories, ...) goes into the bag, stacking.
local common = require("town.common")
local inventory = require("lib.inventory")
local items = require("lib.items")
local php = require("lib.php")
local view = require("lib.view")

local shop = {}

local ICONS = { weapon = "weapon", armor = "armor", shield = "shield" }

-- Shared buy checks. Returns the offer (item, slot, old entry, sellback, can_keep,
-- can_sell, max qty) or nil, error response.
local function check(req, id)
	local user = req.user
	local town = common.town_here(req)
	if not town then return nil, common.cheat(req) end
	if not items.sold_in(town.id, id) then return nil, common.cheat(req) end
	local item = items.get(id)
	local o = { item = item }
	local bag = inventory.bag(user.id)
	local size = inventory.size()
	if item.slot and item.slot ~= "accessory" then
		local old = inventory.equipped(user.id)[item.slot]
		-- the list never links what you are wearing (legacy let a crafted URL buy it again)
		if old and old.item.id == item.id then return nil, common.cheat(req) end
		o.slot, o.old = item.slot, old
		o.can_sell = old ~= nil and items.can_sell(old.item)
		o.sellback = o.can_sell and items.sell_price(old.item) or 0
		-- the old item can be sold back in the same trade, so its value counts toward the
		-- price (legacy compared gold alone against the full price)
		if user.gold + o.sellback < item.price then
			return nil, common.message(req, "Buy Items", "shop_poor")
		end
		o.keep_full = old ~= nil and inventory.room(old.item, bag, size) == 0
		o.can_keep = old ~= nil and not o.keep_full and user.gold >= item.price
		if old and not o.can_sell and not o.can_keep then
			return nil, common.message(req, "Buy Items", o.keep_full and "shop_bag_full" or "shop_poor")
		end
	else
		local room = inventory.room(item, bag, size)
		if room == 0 then return nil, common.message(req, "Buy Items", "shop_bag_full") end
		local afford = item.price > 0 and php.floor(user.gold / item.price) or room
		if afford < 1 then return nil, common.message(req, "Buy Items", "shop_poor") end
		o.max = math.min(room, afford)
	end
	return o
end

-- GET /shop
function shop.list(req)
	local user = req.user
	local town = common.town_here(req)
	if not town then return common.cheat(req) end
	local eq = inventory.equipped(user.id)
	local list = {}
	for _, it in ipairs(items.town(town.id)) do
		local line
		if it.attack ~= 0 or it.slot == "weapon" then
			line = "Attack Power: " .. it.attack
		elseif it.defense ~= 0 or it.slot == "armor" or it.slot == "shield" then
			line = "Defense Power: " .. it.defense
		else
			line = table.concat(items.is_gear(it) and items.special_lines(it) or items.use_lines(it), ", ")
		end
		list[#list + 1] = {
			item = it, icon = ICONS[it.slot], line = line,
			owned = it.slot ~= nil and eq[it.slot] ~= nil and eq[it.slot].item.id == it.id,
			special = #it.modifiers > 0 and it.slot ~= "accessory",
		}
	end
	local sell = {}
	for _, e in ipairs(inventory.bag(user.id)) do
		if items.can_sell(e.item) then sell[#sell + 1] = { entry = e, price = items.sell_price(e.item) } end
	end
	return view.page(req, "Buy Items", "town/shop", { items = list, sell = sell })
end

-- GET /shop/buy/#id
function shop.confirm(req, params)
	local o, err = check(req, params.id)
	if not o then return err end
	return view.page(req, "Buy Items", "town/shop_buy", o)
end

-- POST /shop/buy/#id
function shop.buy(req, params)
	local form = req.form
	if form.cancel ~= nil then return view.redirect("/") end
	local o, err = check(req, params.id)
	if not o then return err end
	local user, item = req.user, o.item

	if o.slot then
		local mode = "new"
		if o.old then
			-- "submit" alone (the original form's Yes) sells the old item, as the original did
			mode = form.keep ~= nil and "keep" or "sell"
		end
		local gold = user.gold - item.price
		if mode == "keep" and not o.can_keep then
			return common.message(req, "Buy Items", o.keep_full and "shop_bag_full" or "shop_poor")
		elseif mode == "sell" then
			if not o.can_sell then return common.cheat(req) end
			gold = gold + o.sellback
			dk.db:exec("DELETE FROM user_items WHERE id = ?", o.old.id)
		elseif mode == "new" and gold < 0 then
			return common.message(req, "Buy Items", "shop_poor")
		end
		dk.db:exec("UPDATE users SET gold = ? WHERE id = ?", gold, user.id)
		inventory.equip_new(user.id, item, o.slot)
		return common.message(req, "Buy Items", "shop_done")
	end

	local qty = form.qty == nil and 1 or php.intval(form.qty)
	if qty < 1 or qty > o.max then
		return common.message(req, "Buy Items", "shop_qty", { max = o.max })
	end
	if not inventory.add(user.id, item, qty) then return common.message(req, "Buy Items", "shop_bag_full") end
	dk.db:exec("UPDATE users SET gold = ? WHERE id = ?", user.gold - qty * item.price, user.id)
	return common.message(req, "Buy Items", "shop_done")
end

-- POST /shop/sell/#id: qty (default 1) of a sellable bag entry.
function shop.sell(req, params)
	local user = req.user
	if not common.town_here(req) then return common.cheat(req) end
	local e = inventory.entry(user.id, params.id)
	if not e or e.equipped or not items.can_sell(e.item) then return common.cheat(req) end
	local qty = req.form.qty == nil and 1 or php.intval(req.form.qty)
	if qty < 1 or qty > e.qty then
		return common.message(req, "Sell Items", "shop_qty", { max = e.qty })
	end
	local gold = qty * items.sell_price(e.item)
	inventory.take(e, qty)
	dk.db:exec("UPDATE users SET gold = gold + ? WHERE id = ?", gold, user.id)
	return common.message(req, "Sell Items", "shop_sold", { qty = qty, name = e.item.name, gold = gold })
end

return shop
