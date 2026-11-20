-- inventory.lua :: what characters carry (user_items) and the stats it gives them.
--
-- A user_items row is a stack of one item: equipped in a slot (weapon, armor, shield,
-- accessory1-3) or in the bag (equipped NULL). The bag holds control.inventory_size
-- stacks: equipped items don't count, a stack counts once whatever its qty, and quest
-- items never count (so a quest can't be blocked by a full bag). Adding to a stack that
-- isn't full (qty < max_stack) is always allowed. The pure rules (used, room) are
-- unit-tested in tests/lua/test_inventory.lua.
--
-- Effective stats (inventory.stats, game.stats) are lib/stats.lua's derive() of the users
-- row and the equipped items; the equipped items are cached for the request and forgotten
-- by every change made here. After an equipment change, current HP/MP/TP are clamped to
-- the new maxima (inventory.changed).
--
-- Items that cast a spell (lib/items.lua items.casts) have charges per row
-- (user_items.charges): full (items.charges) when obtained, one spent per cast, refilled
-- for the equipped ones at an inn (inventory.recharge); a single-use one (not
-- rechargeable) is gone with its last charge.
local items = require("lib.items")
local stats = require("lib.stats")

local inventory = {}

inventory.SLOTS = { "weapon", "armor", "shield", "accessory1", "accessory2", "accessory3" }
inventory.ACCESSORY_SLOTS = { "accessory1", "accessory2", "accessory3" }
inventory.LABELS = {
	weapon = "Weapon", armor = "Armor", shield = "Shield",
	accessory1 = "Slot 1", accessory2 = "Slot 2", accessory3 = "Slot 3",
}
local SLOT_SET = {}
for _, s in ipairs(inventory.SLOTS) do SLOT_SET[s] = true end

function inventory.valid_slot(slot)
	return SLOT_SET[slot] == true
end

-- The user_items slots an item can go in: { "weapon" } or the three accessory slots.
function inventory.slots_for(item)
	if item.slot == "accessory" then return inventory.ACCESSORY_SLOTS end
	if item.slot then return { item.slot } end
	return {}
end

-- control.inventory_size (bag stacks).
function inventory.size()
	return dk.db:value("SELECT inventory_size FROM control WHERE id = 1") or 12
end

---------------------------------------------------------------------------------------
-- Pure rules. `bag`: entries ({ qty, item = items row }) not equipped.

-- Bag stacks that count against the size (quest items don't).
function inventory.used(bag)
	local n = 0
	for _, e in ipairs(bag) do
		if e.item.category ~= "quest" then n = n + 1 end
	end
	return n
end

-- How many of `item` can go into the bag in one go: n and the stack they go onto (an
-- entry that isn't full), or n and nil for a new stack (a free slot or a quest item), or 0.
function inventory.room(item, bag, size)
	for _, e in ipairs(bag) do
		if e.item.id == item.id and e.qty < item.max_stack then return item.max_stack - e.qty, e end
	end
	if item.category == "quest" or inventory.used(bag) < size then return item.max_stack, nil end
	return 0, nil
end

-- Free bag slots (never below 0, even if an admin shrank the bag).
function inventory.free(bag, size)
	return math.max(0, size - inventory.used(bag))
end

---------------------------------------------------------------------------------------
-- Reading.

local cache = {}   -- user id -> equipped entries (this request only)

local function entry_of(r)
	local e = { id = r.entry_id, user_id = r.entry_user, qty = r.entry_qty, equipped = r.entry_equipped,
		charges = r.entry_charges }
	r.entry_id, r.entry_user, r.entry_qty, r.entry_equipped, r.entry_charges = nil, nil, nil, nil, nil
	e.item = items.decode(r)
	return e
end

local SELECT = "SELECT ui.id AS entry_id, ui.user_id AS entry_user, ui.qty AS entry_qty, " ..
							 "ui.equipped AS entry_equipped, ui.charges AS entry_charges, i.* FROM user_items ui JOIN items i ON i.id = ui.item_id "

-- Every entry of a user: { id, user_id, qty, equipped, charges, item }, by entry id.
function inventory.entries(user_id)
	local out = {}
	for _, r in ipairs(dk.db:query(SELECT .. "WHERE ui.user_id = ? ORDER BY ui.id", user_id)) do
		out[#out + 1] = entry_of(r)
	end
	return out
end

-- The user's entry `entry_id`, or nil.
function inventory.entry(user_id, entry_id)
	local r = dk.db:first(SELECT .. "WHERE ui.user_id = ? AND ui.id = ?", user_id, entry_id)
	return r and entry_of(r)
end

-- Equipped entries: { slot -> entry }.
function inventory.equipped(user_id)
	if not cache[user_id] then
		local out = {}
		for _, r in ipairs(dk.db:query(SELECT .. "WHERE ui.user_id = ? AND ui.equipped IS NOT NULL", user_id)) do
			local e = entry_of(r)
			out[e.equipped] = e
		end
		cache[user_id] = out
	end
	return cache[user_id]
end

-- Bag entries, by entry id.
function inventory.bag(user_id)
	local out = {}
	for _, r in ipairs(dk.db:query(SELECT .. "WHERE ui.user_id = ? AND ui.equipped IS NULL ORDER BY ui.id", user_id)) do
		out[#out + 1] = entry_of(r)
	end
	return out
end

-- The first bag entry of item `item_id`, or nil.
function inventory.find(user_id, item_id)
	local r = dk.db:first(SELECT .. "WHERE ui.user_id = ? AND ui.item_id = ? AND ui.equipped IS NULL " ..
												"ORDER BY ui.qty, ui.id LIMIT 1", user_id, item_id)
	return r and entry_of(r)
end

-- Effective stats of a users row (lib/stats.lua) with what it has equipped.
function inventory.stats(user)
	local list = {}
	for _, slot in ipairs(inventory.SLOTS) do
		local e = inventory.equipped(user.id)[slot]
		if e then list[#list + 1] = e.item end
	end
	return stats.derive(user, stats.item_mods(list))
end

-- The equipped item's name per slot ("None" when empty): { weapon = "Stick", ... }.
function inventory.names(user_id)
	local eq = inventory.equipped(user_id)
	local out = {}
	for _, slot in ipairs(inventory.SLOTS) do out[slot] = eq[slot] and eq[slot].item.name or "None" end
	return out
end

---------------------------------------------------------------------------------------
-- Changing. Callers check the rules (room, slots, ownership) first.

-- Forget the cached equipment and clamp current HP/MP/TP to the (new) maxima.
function inventory.changed(user_id)
	cache[user_id] = nil
	local user = dk.db:first("SELECT * FROM users WHERE id = ?", user_id)
	if not user then return end
	local c = stats.clamped(user, inventory.stats(user))
	if c.currenthp ~= user.currenthp or c.currentmp ~= user.currentmp or c.currenttp ~= user.currenttp then
		dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
							 c.currenthp, c.currentmp, c.currenttp, user_id)
	end
end

-- Puts `qty` of `item` into the bag (onto a stack that isn't full, else a new stack).
-- Returns false (and changes nothing) when it doesn't fit (inventory.room).
function inventory.add(user_id, item, qty)
	local n, stack = inventory.room(item, inventory.bag(user_id), inventory.size())
	if qty < 1 or qty > n then return false end
	if stack then
		dk.db:exec("UPDATE user_items SET qty = qty + ? WHERE id = ?", qty, stack.id)
	else
		dk.db:exec("INSERT INTO user_items (user_id, item_id, qty, charges) VALUES (?, ?, ?, ?)", user_id, item.id, qty,
							 inventory.full_charges(item))
	end
	return true
end

-- Takes `qty` (default all) off an entry; the row goes when it is empty.
function inventory.take(entry, qty)
	qty = qty or entry.qty
	if qty >= entry.qty then
		dk.db:exec("DELETE FROM user_items WHERE id = ?", entry.id)
	else
		dk.db:exec("UPDATE user_items SET qty = qty - ? WHERE id = ?", qty, entry.id)
	end
	if entry.equipped then inventory.changed(entry.user_id) end
end

-- Equips bag entry `entry` (gear) in `slot` (one of inventory.slots_for(entry.item)); the
-- item there goes into the bag in its place, so this never needs a free slot. Returns the
-- entry that was in the slot, or nil.
function inventory.equip(user_id, entry, slot)
	local old = inventory.equipped(user_id)[slot]
	dk.db:exec("UPDATE user_items SET equipped = NULL WHERE user_id = ? AND equipped = ?", user_id, slot)
	if entry.qty > 1 then
		dk.db:exec("UPDATE user_items SET qty = qty - 1 WHERE id = ?", entry.id)
		dk.db:exec("INSERT INTO user_items (user_id, item_id, qty, equipped, charges) VALUES (?, ?, 1, ?, ?)",
							 user_id, entry.item.id, slot, entry.charges)
	else
		dk.db:exec("UPDATE user_items SET equipped = ? WHERE id = ?", slot, entry.id)
	end
	inventory.changed(user_id)
	return old
end

-- Equips `item` (new: bought) in `slot`; whatever is still in the slot goes into the bag.
-- One clamp of current HP/MP/TP at the end (like the original shop's single update).
function inventory.equip_new(user_id, item, slot)
	dk.db:exec("UPDATE user_items SET equipped = NULL WHERE user_id = ? AND equipped = ?", user_id, slot)
	dk.db:exec("INSERT INTO user_items (user_id, item_id, qty, equipped, charges) VALUES (?, ?, 1, ?, ?)", user_id,
						 item.id, slot, inventory.full_charges(item))
	inventory.changed(user_id)
end

-- Moves what is in `slot` into the bag (the caller checked for a free slot).
function inventory.unequip(user_id, slot)
	local e = inventory.equipped(user_id)[slot]
	if not e then return nil end
	dk.db:exec("UPDATE user_items SET equipped = NULL WHERE id = ?", e.id)
	inventory.changed(user_id)
	return e
end

-- The charges a newly obtained `item` has: all of them for an item that casts, else 0.
function inventory.full_charges(item)
	return items.casts(item) and item.charges or 0
end

-- Spends one charge of `entry` (an item that casts; the caller checked it has one). A
-- single-use item (not rechargeable) is used up with its last charge: true then.
function inventory.spend_charge(entry)
	if entry.charges <= 1 and not items.rechargeable(entry.item) then
		dk.db:exec("DELETE FROM user_items WHERE id = ?", entry.id)
		inventory.changed(entry.user_id)
		return true
	end
	dk.db:exec("UPDATE user_items SET charges = charges - 1 WHERE id = ? AND charges > 0", entry.id)
	cache[entry.user_id] = nil
	return false
end

-- Refills the charges of the user's equipped items that cast and are rechargeable (the
-- inn); bag items keep theirs. Returns the entries that were recharged, in slot order.
function inventory.recharge(user_id)
	local out = {}
	for _, slot in ipairs(inventory.SLOTS) do
		local e = inventory.equipped(user_id)[slot]
		if e and items.casts(e.item) and items.rechargeable(e.item) and e.charges < e.item.charges then
			dk.db:exec("UPDATE user_items SET charges = ? WHERE id = ?", e.item.charges, e.id)
			out[#out + 1] = e
		end
	end
	cache[user_id] = nil
	return out
end

-- The first empty accessory slot, or nil.
function inventory.free_accessory_slot(user_id)
	local eq = inventory.equipped(user_id)
	for _, slot in ipairs(inventory.ACCESSORY_SLOTS) do
		if not eq[slot] then return slot end
	end
	return nil
end

return inventory
