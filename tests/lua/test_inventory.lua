-- Unit tests for the pure inventory rules of lib/inventory.lua: the bag size, stacks,
-- quest items, slots.
local inventory = require("lib.inventory")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- bag entries
local HERB = { id = 66, category = "consumable", max_stack = 10 }
local STICK = { id = 1, category = "weapon", max_stack = 1 }
local KEY = { id = 90, category = "quest", max_stack = 1 }
local function entry(item, qty) return { item = item, qty = qty or 1 } end
local function bag_of(n, item)
	local b = {}
	for i = 1, n do b[i] = entry(item or { id = 100 + i, category = "misc", max_stack = 1 }) end
	return b
end

function T.inventory_cap()
	-- an empty bag of 12
	local n, stack = inventory.room(HERB, {}, 12)
	eq(n, 10); eq(stack, nil)
	-- a stack counts once; topping it up is allowed even when the bag is full
	local bag = bag_of(11)
	bag[12] = entry(HERB, 4)
	eq(inventory.used(bag), 12); eq(inventory.free(bag, 12), 0)
	n, stack = inventory.room(HERB, bag, 12)
	eq(n, 6); eq(stack, bag[12])
	-- a full stack needs a new slot
	bag[12].qty = 10
	eq(inventory.room(HERB, bag, 12), 0)
	eq(inventory.room(STICK, bag, 12), 0)
	-- with a free slot: a new stack
	n, stack = inventory.room(HERB, bag_of(11), 12)
	eq(n, 10); eq(stack, nil)
	-- quest items don't count and always fit
	bag = bag_of(12)
	bag[13] = entry(KEY)
	eq(inventory.used(bag), 12)
	n = inventory.room(KEY, bag, 12)
	eq(n, 1)
	eq(inventory.room(STICK, bag, 12), 0)
	-- equipped items aren't in the bag (callers pass bag entries only); an over-full bag
	-- (the admin shrank it) has no free slots
	eq(inventory.free(bag_of(15), 12), 0); eq(inventory.room(STICK, bag_of(15), 12), 0)
	-- slots
	eq(table.concat(inventory.slots_for({ slot = "accessory" }), ","), "accessory1,accessory2,accessory3")
	eq(table.concat(inventory.slots_for({ slot = "shield" }), ","), "shield")
	eq(#inventory.slots_for({ category = "consumable" }), 0)
	assert(inventory.valid_slot("accessory2") and not inventory.valid_slot("accessory4") and not inventory.valid_slot("id"))
end

return T
