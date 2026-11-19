-- town/inventory.lua :: /inventory -- what the character has equipped and in the bag,
-- and the actions on it (equip, unequip, use, discard). The rules are lib/inventory.lua's;
-- every action is a POST (CSRF) that renders the page again with what happened.
local common = require("town.common")
local effects = require("lib.effects")
local game = require("lib.game")
local inventory = require("lib.inventory")
local items = require("lib.items")
local php = require("lib.php")
local view = require("lib.view")

local inv = {}

-- effects.refusal() -> what the page says
local FULL = {
	hp_full = "Your Hit Points are already full. You don't need to use the %s now.",
	mp_full = "Your Magic Points are already full. You don't need to use the %s now.",
	tp_full = "Your Travel Points are already full. You don't need to use the %s now.",
	fight_only = "The %s can only be used in a fight.",
	cannot = "The %s can't be used.",
}

local function page(req, notice)
	local user = game.user(req.user.id)   -- fresh: the action may have changed it
	local size = inventory.size()
	local bag = inventory.bag(user.id)
	local eq = inventory.equipped(user.id)
	local free = inventory.free(bag, size)
	local slots = {}
	for _, slot in ipairs(inventory.SLOTS) do
		local e = eq[slot]
		slots[#slots + 1] = { slot = slot, label = inventory.LABELS[slot], entry = e,
													attributes = e and items.attributes(e.item) or nil }
	end
	local cells = {}
	for _, e in ipairs(bag) do
		local it = e.item
		cells[#cells + 1] = {
			entry = e, item = it, gear = items.is_gear(it), accessory = it.slot == "accessory",
			quest = it.category == "quest", usable = items.usable(it, "town"),
			lines = items.is_gear(it) and items.attributes(it) or items.effect_lines(it),
		}
	end
	return view.page(req, "Inventory", "town/inventory", {
		slots = slots, cells = cells, used = inventory.used(bag), size = size,
		empty = free, u = user, s = game.stats(user), notice = notice,
	})
end

-- GET /inventory
function inv.show(req)
	return page(req)
end

-- A bag entry of the user, or nil.
local function bag_entry(req, id)
	local e = inventory.entry(req.user.id, id)
	if not e or e.equipped then return nil end
	return e
end

-- POST /inventory/equip/#id: gear from the bag into its slot (accessories: slot=1-3, or
-- 0/absent for the first free one); what was there goes into the bag.
function inv.equip(req, params)
	local user = req.user
	local e = bag_entry(req, params.id)
	if not e or not items.is_gear(e.item) then return common.cheat(req) end
	local slot = e.item.slot
	if slot == "accessory" then
		local n = php.intval(req.form.slot)
		if n == 0 then
			slot = inventory.free_accessory_slot(user.id)
			if not slot then
				return page(req, { "All three accessory slots are in use. Choose the slot for the " .. e.item.name ..
					" (the item in it goes into your bag)." })
			end
		elseif n >= 1 and n <= 3 then
			slot = "accessory" .. n
		else
			return common.cheat(req)
		end
	end
	local old = inventory.equip(user.id, e, slot)
	local msg = "You equipped the " .. e.item.name .. "."
	if old then msg = msg .. " The " .. old.item.name .. " is in your bag now." end
	return page(req, { msg })
end

-- POST /inventory/unequip/:slot: into the bag, which needs a free slot.
function inv.unequip(req, params)
	local user = req.user
	if not inventory.valid_slot(params.slot) then return common.cheat(req) end
	local e = inventory.equipped(user.id)[params.slot]
	if not e then return page(req, { "There is nothing to take off there." }) end
	if inventory.room(e.item, inventory.bag(user.id), inventory.size()) == 0 then
		return page(req, { "Your bag is full. Make room in it before you take off the " .. e.item.name .. "." })
	end
	inventory.unequip(user.id, params.slot)
	return page(req, { "You took off the " .. e.item.name .. ". It is in your bag now." })
end

-- POST /inventory/use/#id: a consumable whose effects work outside fights.
function inv.use(req, params)
	local user = req.user
	local e = bag_entry(req, params.id)
	if not e then return common.cheat(req) end
	local item = e.item
	local st = game.player(user)
	local refused = not items.usable(item, "town") and (item.category == "consumable" and "fight_only" or "cannot") or
									effects.refusal(item.use_effects, { player = st, in_fight = false })
	if refused then return page(req, { (FULL[refused] or FULL.cannot):format(item.name) }) end
	local lines = effects.apply(item.use_effects, { player = st, in_fight = false, intro = "You have used the " .. item.name })
	inventory.take(e, 1)
	dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
						 php.mysql_uint(st.currenthp), php.mysql_uint(st.currentmp), php.mysql_uint(st.currenttp), user.id)
	return page(req, lines)
end

-- GET /inventory/discard/#id: confirmation (how many, for a stack).
function inv.discard_confirm(req, params)
	local e = bag_entry(req, params.id)
	if not e then return common.cheat(req) end
	if e.item.category == "quest" then return page(req, { "Quest items can't be discarded." }) end
	return view.page(req, "Inventory", "town/inventory_discard", { entry = e })
end

-- POST /inventory/discard/#id: qty (default: the whole stack); "cancel" goes back.
function inv.discard(req, params)
	if req.form.cancel ~= nil then return view.redirect("/inventory") end
	local e = bag_entry(req, params.id)
	if not e then return common.cheat(req) end
	if e.item.category == "quest" then return page(req, { "Quest items can't be discarded." }) end
	local qty = req.form.qty and php.intval(req.form.qty) or e.qty
	if qty < 1 or qty > e.qty then
		return view.page(req, "Inventory", "town/inventory_discard", {
			entry = e, error = "Please enter a number from 1 to " .. e.qty .. "." })
	end
	inventory.take(e, qty)
	return page(req, { "You discarded " .. (qty > 1 and (qty .. " x ") or "the ") .. e.item.name .. "." })
end

return inv
