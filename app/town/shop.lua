-- town/shop.lua :: legacy towns.php buy() / buy2() / buy3(), with the bag: the town's
-- market (3.1: the shop and the map store, town/maps.lua): its items (town_items), its maps
-- (town_maps) and selling bag items back.
--   GET  /shop               the town's items (icon buttons by group), its maps + the Sell
--                            section (sellable bag items)
--   GET  /shop/buy/#id       confirmation; POST: gear (weapons, armor, shields) "bag" (into
--                            the bag; what is worn stays), "keep" (worn; the old item goes
--                            into the bag: needs a free slot) or "sell" (worn; the old item
--                            is sold back, its value counts toward the price); "submit"
--                            alone wears it (selling the old one, as the original did); bag
--                            items: "submit" with qty
--   POST /shop/sell/#id      a bag entry (qty for stacks), for items.sell_price each
-- Weapons, armor and shields are worn when bought or put into the bag (3.0: the player
-- chooses); everything else (consumables, accessories, ...) goes into the bag, stacking. Any item the town sells can be bought
-- again and again, as far as the gold and the bag allow (2.4: a copy of the weapon you
-- wear too; the old one is kept in the bag or sold, as always).
local common = require("town.common")
local game = require("lib.game")
local inventory = require("lib.inventory")
local items = require("lib.items")
local php = require("lib.php")
local tips = require("lib.tips")
local view = require("lib.view")

local shop = {}

-- the group of an item by its slot (accessories, consumables, ...: "other")
local SLOT_GROUP = { weapon = "weapon", armor = "armor", shield = "shield" }

-- Shared buy checks. Returns the offer (item, slot, old entry, sellback, can_bag, bag_full,
-- can_keep, keep_full, can_sell, max qty) or nil, error response.
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
		-- a copy of what you are wearing is fine too (2.4: no more "Already purchased")
		local old = inventory.equipped(user.id)[item.slot]
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
		o.bag_full = inventory.room(item, bag, size) == 0
		o.can_bag = not o.bag_full and user.gold >= item.price
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

-- The shop's groups of items, in order (an item's slot; anything else is an "Item").
local GROUPS = { { key = "weapon", label = "Weapons" }, { key = "armor", label = "Armor" },
	{ key = "shield", label = "Shields" }, { key = "other", label = "Items" } }

-- GET /shop: the town's items as icon buttons in groups ({ key, label, items = { item,
-- icon (URL: its picture or the default one), label, tip (tips.shop: the price is in it),
-- short (the gold doesn't cover it now: greyed out; the purchase page says why) } }; empty
-- groups left out), the maps the town sells (game.town_maps: { town, mapped (on the
-- player's map already), short (the gold doesn't cover it), latitude, longitude }) and the
-- Sell section (sellable bag entries: { entry, price (each), icon, label, tip (tips.sell)
-- }). The town's market (3.1: the shop and the map store in one).
function shop.list(req)
	local user = req.user
	local town = common.town_here(req)
	if not town then return common.cheat(req) end
	local equipped = inventory.equipped(user.id)
	local by_key, groups = {}, {}
	for _, g in ipairs(GROUPS) do by_key[g.key] = { key = g.key, label = g.label, items = {} } end
	for _, it in ipairs(items.town(town.id)) do
		-- gear replaces what is in its slot, whose sell-back counts toward the price (check())
		local old = it.slot and it.slot ~= "accessory" and equipped[it.slot] or nil
		local sellback = old and items.can_sell(old.item) and items.sell_price(old.item) or 0
		local short = user.gold + sellback < it.price
		local g = by_key[SLOT_GROUP[it.slot] or "other"]
		g.items[#g.items + 1] = { item = it, icon = items.icon_url(it), short = short,
			tip = tips.shop(it, { gold = user.gold, old = old, sellback = sellback, short = short }),
			label = it.name .. " (" .. it.price .. " gold)" }
	end
	for _, g in ipairs(GROUPS) do
		if #by_key[g.key].items > 0 then groups[#groups + 1] = by_key[g.key] end
	end
	local sell = {}
	for _, e in ipairs(inventory.bag(user.id)) do
		if items.can_sell(e.item) then
			local price = items.sell_price(e.item)
			sell[#sell + 1] = { entry = e, price = price, icon = items.icon_url(e.item), tip = tips.sell(e, price),
				label = "Sell " .. e.item.name .. " for " .. price .. " gold" .. (e.qty > 1 and " each" or "") }
		end
	end
	local maps = {}
	for _, t in ipairs(game.town_maps(town.id)) do
		maps[#maps + 1] = { town = t, mapped = php.in_list(user.towns, t.id), short = user.gold < t.mapprice,
			latitude = game.latitude_str(t.latitude), longitude = game.longitude_str(t.longitude) }
	end
	return view.page(req, "Market", "town/shop", { groups = groups, maps = maps, sell = sell })
end

-- GET /shop/buy/#id: the purchase (the shop's dialog: its links have data-modal; a page
-- of its own without JavaScript), templates/town/shop_buy.html: check()'s offer, and icon
-- (URL), kind, gold, stats (what it gives, as text: { label, new, old, delta, better }; old
-- and delta against the item worn in its slot), effects (a consumable's, the spell it
-- casts), description (gear's), after ({ buy, keep, sell }: the gold each choice leaves).
function shop.confirm(req, params)
	local o, err = check(req, params.id)
	if not o then return err end
	local it, gold = o.item, req.user.gold
	o.icon, o.kind, o.gold = items.icon_url(it), items.category_label(it), gold
	o.stats = {}
	for _, c in ipairs(items.compare(it, o.old and o.old.item)) do
		o.stats[#o.stats + 1] = { label = c.label, new = c.new and items.signed(c.stat, c.new) or "—",
			old = c.old and items.signed(c.stat, c.old) or "—",
			delta = c.delta ~= 0 and items.signed(c.stat, c.delta) or nil, better = c.delta > 0 }
	end
	o.effects = {}
	if it.category == "consumable" and (it.description or "") ~= "" then o.effects[1] = it.description end
	for _, l in ipairs(items.charge_lines(it)) do o.effects[#o.effects + 1] = l end
	if it.category ~= "consumable" then o.description = it.description end
	o.after = { buy = gold - it.price, keep = gold - it.price, sell = gold - it.price + (o.sellback or 0) }
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
		if form.bag ~= nil then
			mode = "bag"
		elseif o.old then
			-- "submit" alone (the original form's Yes) sells the old item, as the original did
			mode = form.keep ~= nil and "keep" or "sell"
		end
		local gold = user.gold - item.price
		if mode == "bag" then
			if not o.can_bag then return common.message(req, "Buy Items", o.bag_full and "shop_bag_full" or "shop_poor") end
			if not inventory.add(user.id, item, 1) then return common.message(req, "Buy Items", "shop_bag_full") end
			dk.db:exec("UPDATE users SET gold = ? WHERE id = ?", gold, user.id)
			return common.message(req, "Buy Items", "shop_done")
		elseif mode == "keep" and not o.can_keep then
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
