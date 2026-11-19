-- classes.lua :: character classes as the game uses them (rows of the classes table,
-- synced from app/content/classes/*.lua; see lib/content/). Cached per request.
local classes = {}

local cache = {}

local function all()
	if not cache.all then
		cache.all = dk.db:query("SELECT * FROM classes ORDER BY sort, id")
		cache.by_id = {}
		for _, c in ipairs(cache.all) do cache.by_id[c.id] = c end
	end
	return cache.all
end

-- Forget the cached rows (after a content sync in this request).
function classes.reload()
	cache.all, cache.by_id = nil, nil
end

-- Every class, retired ones too, in sort order.
function classes.all()
	return all()
end

-- Classes offered at registration (playable, not retired), in sort order.
function classes.playable()
	local out = {}
	for _, c in ipairs(all()) do
		if c.playable ~= 0 and c.retired == 0 then out[#out + 1] = c end
	end
	return out
end

-- Classes shown in the help pages (not retired), in sort order.
function classes.active()
	local out = {}
	for _, c in ipairs(all()) do
		if c.retired == 0 then out[#out + 1] = c end
	end
	return out
end

-- The class with id `id` (a users.charclass value), retired or not; nil if none.
function classes.get(id)
	all()
	return cache.by_id[math.tointeger(tonumber(id))]
end

-- By id or key (`dk install --class`).
function classes.find(id_or_key)
	local c = classes.get(id_or_key)
	if c then return c end
	for _, row in ipairs(all()) do
		if row.key == id_or_key then return row end
	end
	return nil
end

-- Class name for a users.charclass value (nil for an unknown class).
function classes.name(id)
	local c = classes.get(id)
	return c and c.name
end

-- users columns of a new character of class `c`.
function classes.start_stats(c)
	return {
		currenthp = c.start_hp, maxhp = c.start_hp,
		currentmp = c.start_mp, maxmp = c.start_mp,
		currenttp = c.start_tp, maxtp = c.start_tp,
		strength = c.start_strength, dexterity = c.start_dexterity,
		attackpower = c.start_strength, defensepower = c.start_dexterity,
	}
end

-- Gains of class `c` per level: { [level] = { hp, mp, strength, dexterity, spells = { id, ... } } }
-- (hp without the milestone bonus; levels 2 .. MAX_LEVEL).
function classes.levels(c)
	local out = {}
	for _, r in ipairs(dk.db:query("SELECT * FROM class_levels WHERE class_id = ? ORDER BY level", c.id)) do
		out[r.level] = { hp = r.hp, mp = r.mp, strength = r.strength, dexterity = r.dexterity, spells = {} }
	end
	for _, s in ipairs(dk.db:query("SELECT level, spell_id FROM class_spells WHERE class_id = ? ORDER BY level, spell_id",
																	c.id)) do
		local g = out[s.level]
		if g then g.spells[#g.spells + 1] = s.spell_id end
	end
	return out
end

return classes
