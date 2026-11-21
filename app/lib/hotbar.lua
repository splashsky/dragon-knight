-- hotbar.lua :: the fight's hotbar (3.1; docs/APP.md "Hotbar"): ten slots on the number
-- keys, 1 Attack and 0 Run (fixed, not stored), 2-9 the player's other fight actions where
-- they put them. An action is the equipped gear that casts, a fight spell known or a fight
-- consumable in the bag (the fight menu's order), keyed "spell:<spells id>" or
-- "item:<items id>". user_hotbar keeps every action a character has met, on the bar (slot
-- 2-9) or off it (slot NULL). One not met yet takes the first free slot, or goes off the
-- bar when none is free: pages show that without writing it (hotbar.arrange: GETs stay
-- pure), and a fight's beginning writes it (hotbar.settle), so the bar never shifts under
-- the player's fingers. One met but not at hand now (a consumable used up, gear not worn, a
-- spell forgotten) keeps its slot.
local inventory = require("lib.inventory")
local items = require("lib.items")
local spells = require("lib.spells")

local hotbar = {}

hotbar.FIRST, hotbar.LAST = 2, 9   -- the slots the player arranges

-- An action's key.
function hotbar.key(kind, id)
	return kind .. ":" .. id
end

-- The kind ("spell" or "item") and id of a key, or nil.
function hotbar.parse(key)
	local kind, id = tostring(key or ""):match("^(%a+):(%d+)$")
	if kind ~= "spell" and kind ~= "item" then return nil end
	return kind, math.tointeger(tonumber(id))
end

local function spell_action(s)
	return { key = hotbar.key("spell", s.id), kind = "spell", id = s.id, name = s.name, icon = spells.icon_url(s), spell = s }
end

local function item_action(it)
	return { key = hotbar.key("item", it.id), kind = "item", id = it.id, name = it.name, icon = items.icon_url(it), item = it }
end

-- The actions `user` can take in a fight now besides Attack and Run, in the fight menu's
-- order (the equipped gear that casts by slot, the fight spells known, the fight
-- consumables in the bag): { key, kind, id, name, icon (URL), spell | item (the row) }.
function hotbar.actions(user)
	local out, seen = {}, {}
	local function add(a)
		if not seen[a.key] then
			seen[a.key] = true
			out[#out + 1] = a
		end
	end
	local eq = inventory.equipped(user.id)
	for _, slot in ipairs(inventory.SLOTS) do
		local e = eq[slot]
		if e and items.casts(e.item) then add(item_action(e.item)) end
	end
	for _, s in ipairs(spells.known(user, "fight")) do add(spell_action(s)) end
	for _, e in ipairs(inventory.bag(user.id)) do
		if items.usable(e.item, "fight") then add(item_action(e.item)) end
	end
	return out
end

-- The action of a key whatever the player has now (a stored one not at hand), or nil when
-- its spell or item is gone from the game.
function hotbar.describe(key)
	local kind, id = hotbar.parse(key)
	if kind == "spell" then
		local s = spells.get(id)
		return s and spell_action(s)
	elseif kind == "item" then
		local it = items.get(id)
		return it and item_action(it)
	end
end

-- The stored rows: slot -> key (on the bar), and the set of keys met.
local function stored(user_id)
	local slots, met = {}, {}
	for _, r in ipairs(dk.db:query("SELECT kind, ref_id, slot FROM user_hotbar WHERE user_id = ?", user_id)) do
		local key = hotbar.key(r.kind, r.ref_id)
		met[key] = true
		if r.slot then slots[r.slot] = key end
	end
	return slots, met
end

-- Where `keys` (the actions at hand, in order) go: the stored slots, then each key not met
-- yet in the first free slot. Returns slot -> key (2-9; stored keys not at hand included),
-- and the new keys: key -> slot (false: off the bar, no slot was free).
local function place(user_id, keys)
	local slots, met = stored(user_id)
	local new = {}
	for _, key in ipairs(keys) do
		if not met[key] and new[key] == nil then
			new[key] = false
			for s = hotbar.FIRST, hotbar.LAST do
				if not slots[s] then
					slots[s] = key
					new[key] = s
					break
				end
			end
		end
	end
	return slots, new
end

local function keys_of(actions)
	local keys = {}
	for i, a in ipairs(actions) do keys[i] = a.key end
	return keys
end

-- The bar as it stands for `user_id` with the actions at hand `keys` (in the fight menu's
-- order): slot -> key, slots 2-9. Reads only.
function hotbar.arrange(user_id, keys)
	return (place(user_id, keys))
end

-- Writes where the actions at hand not met yet go (a fight begins: the bar is fixed from
-- here on).
function hotbar.settle(user)
	local _, new = place(user.id, keys_of(hotbar.actions(user)))
	for key, slot in pairs(new) do
		local kind, id = hotbar.parse(key)
		dk.db:exec("INSERT INTO user_hotbar (user_id, kind, ref_id, slot) VALUES (?, ?, ?, ?)", user.id, kind, id,
			slot or nil)
	end
end

-- The keys the player may put on the bar: the actions at hand and those on the bar now.
function hotbar.choices(user)
	local list, seen = {}, {}
	for _, a in ipairs(hotbar.actions(user)) do
		list[#list + 1] = a
		seen[a.key] = true
	end
	local slots = stored(user.id)
	for s = hotbar.FIRST, hotbar.LAST do
		local key = slots[s]
		if key and not seen[key] then
			local a = hotbar.describe(key)
			if a then
				list[#list + 1] = a
				seen[key] = true
			end
		end
	end
	return list, seen
end

-- Puts `chosen` (slot -> key, slots 2-9; keys from hotbar.choices) on the bar; every
-- other action met or at hand goes off it.
function hotbar.save(user, chosen)
	local _, met = stored(user.id)
	for _, a in ipairs(hotbar.actions(user)) do met[a.key] = true end
	for s = hotbar.FIRST, hotbar.LAST do
		if chosen[s] then met[chosen[s]] = true end
	end
	local at = {}
	for s = hotbar.FIRST, hotbar.LAST do
		if chosen[s] then at[chosen[s]] = s end
	end
	dk.db:exec("DELETE FROM user_hotbar WHERE user_id = ?", user.id)
	for key in pairs(met) do
		local kind, id = hotbar.parse(key)
		dk.db:exec("INSERT INTO user_hotbar (user_id, kind, ref_id, slot) VALUES (?, ?, ?, ?)", user.id, kind, id, at[key])
	end
end

-- Forgets the arrangement: the bar fills again from what the player has (at the next
-- fight; pages show it so at once).
function hotbar.reset(user_id)
	dk.db:exec("DELETE FROM user_hotbar WHERE user_id = ?", user_id)
end

return hotbar
