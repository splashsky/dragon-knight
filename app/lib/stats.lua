-- stats.lua :: derived character stats (pure functions, no DB; unit-tested in
-- tests/lua/test_stats.lua).
--
-- A users row holds the *base* stats: base_maxhp, base_maxmp, base_maxtp, strength and
-- dexterity (grown by level-ups), plus base_attack, base_defense, base_exp_bonus and
-- base_gold_bonus (0 for every new character: power that comes from neither strength,
-- dexterity nor gear; schema version 6 kept the legacy differences there, and admins can
-- set them). The equipped items add their attack, defense and stat modifiers. Effective:
--   maxhp/maxmp/maxtp, strength, dexterity = base + modifiers
--   attack  = strength + base_attack  + Σ attack  (item attack + attack modifiers)
--   defense = dexterity + base_defense + Σ defense
--   exp_bonus_pct / gold_bonus_pct = base + Σ
-- Stats that were UNSIGNED columns in the original game (all but the bonuses) never go
-- below 0, as MySQL clamped them. lib/inventory.lua computes them once per request
-- (game.stats(user)).
--
-- Gear's passive modifiers are data: a list of { kind = "stat", stat = "strength",
-- amount = 50 } in the item files (checked by stats.validate_modifiers), stored as text
-- ("stat stat=strength amount=50; stat stat=maxhp amount=-50") and summed while equipped.
local stats = {}

stats.STATS = {
	"maxhp", "maxmp", "maxtp", "strength", "dexterity", "attack", "defense", "exp_bonus_pct", "gold_bonus_pct",
}
local STAT_SET = {}
for _, s in ipairs(stats.STATS) do STAT_SET[s] = true end

-- The range of a modifier's amount.
stats.AMOUNT = { min = -1000000, max = 1000000 }

-- stat -> the users column holding its base value
stats.BASE = {
	maxhp = "base_maxhp", maxmp = "base_maxmp", maxtp = "base_maxtp", strength = "strength",
	dexterity = "dexterity", attack = "base_attack", defense = "base_defense",
	exp_bonus_pct = "base_exp_bonus", gold_bonus_pct = "base_gold_bonus",
}

local SIGNED = { exp_bonus_pct = true, gold_bonus_pct = true }

-- Sum of what `items` (rows with attack, defense and decoded modifiers) add:
-- { attack = 250, strength = 50, ... } (absent = 0).
function stats.item_mods(items)
	local sum = {}
	local function add(stat, n)
		if n and n ~= 0 then sum[stat] = (sum[stat] or 0) + n end
	end
	for _, it in ipairs(items) do
		add("attack", it.attack)
		add("defense", it.defense)
		for stat, n in pairs(stats.modifiers(it.modifiers or {})) do add(stat, n) end
	end
	return sum
end

local function max0(n)
	if n < 0 then return 0 end
	return n
end

-- Effective stats from a users row's base columns and the summed item modifiers.
function stats.derive(base, mods)
	local function m(stat) return mods[stat] or 0 end
	local strength = base.strength + m("strength")
	local dexterity = base.dexterity + m("dexterity")
	return {
		maxhp = max0(base.base_maxhp + m("maxhp")),
		maxmp = max0(base.base_maxmp + m("maxmp")),
		maxtp = max0(base.base_maxtp + m("maxtp")),
		strength = max0(strength),
		dexterity = max0(dexterity),
		attack = max0(strength + base.base_attack + m("attack")),
		defense = max0(dexterity + base.base_defense + m("defense")),
		exp_bonus_pct = base.base_exp_bonus + m("exp_bonus_pct"),
		gold_bonus_pct = base.base_gold_bonus + m("gold_bonus_pct"),
	}
end

-- The base columns that make derive() give `expected` (effective stats, never below 0
-- where derive clamps) with `mods`: { base_maxhp = ..., strength = ..., base_attack = ... }.
-- Used to convert stored stats into base stats (schema version 6) and to keep a
-- character's effective stats when the items' values changed under them.
function stats.solve(expected, mods)
	local function m(stat) return mods[stat] or 0 end
	local base = {}
	for _, stat in ipairs(stats.STATS) do
		if stat ~= "attack" and stat ~= "defense" then
			assert(SIGNED[stat] or expected[stat] >= 0, "negative " .. stat)
			base[stats.BASE[stat]] = expected[stat] - m(stat)
		end
	end
	base.base_attack = expected.attack - expected.strength - m("attack")
	base.base_defense = expected.defense - expected.dexterity - m("defense")
	return base
end

-- The stats that differ between two derive() results: { "attack", ... } (in STATS order).
function stats.diff(a, b)
	local out = {}
	for _, stat in ipairs(stats.STATS) do
		if a[stat] ~= b[stat] then out[#out + 1] = stat end
	end
	return out
end

-- A copy of the users row with the effective stats under the names the fight code and
-- the spell and item actions use (the original game's users columns): maxhp, maxmp, maxtp,
-- strength, dexterity, attackpower, defensepower, expbonus, goldbonus.
function stats.player(user, s)
	local p = {}
	for k, v in pairs(user) do p[k] = v end
	p.maxhp, p.maxmp, p.maxtp = s.maxhp, s.maxmp, s.maxtp
	p.strength, p.dexterity = s.strength, s.dexterity
	p.attackpower, p.defensepower = s.attack, s.defense
	p.expbonus, p.goldbonus = s.exp_bonus_pct, s.gold_bonus_pct
	return p
end

-- Current HP/MP/TP clamped to the effective maxima: { currenthp, currentmp, currenttp }.
function stats.clamped(user, s)
	return {
		currenthp = math.min(user.currenthp, s.maxhp),
		currentmp = math.min(user.currentmp, s.maxmp),
		currenttp = math.min(user.currenttp, s.maxtp),
	}
end

-- A monster's effective numbers with the summed modifiers of its equipment (item_mods), by
-- the players' rules (derive): its maxhp, maxmp are the base maxima, strength and
-- dexterity 0, its maxdam the base attack and its armor the base defense. So maxdam =
-- maxdam + strength + attack, armor = armor + dexterity + defense, maxhp/maxmp + theirs;
-- without equipment the numbers are the row's (maxhp at least 1). (The experience and gold
-- bonuses of gear don't apply to monsters.) Returns { maxhp, maxmp, maxdam, armor,
-- strength, dexterity }.
function stats.monster(m, mods)
	local d = stats.derive({
		base_maxhp = m.maxhp, base_maxmp = m.maxmp or 0, base_maxtp = 0, strength = 0, dexterity = 0,
		base_attack = m.maxdam, base_defense = m.armor, base_exp_bonus = 0, base_gold_bonus = 0,
	}, mods)
	return { maxhp = math.max(1, d.maxhp), maxmp = d.maxmp, maxdam = d.attack, armor = d.defense, strength = d.strength,
		dexterity = d.dexterity }
end

---------------------------------------------------------------------------------------
-- Modifiers (gear's stat bonuses while equipped).

-- Checks a list of modifiers from an item file. Returns a normalized copy, or nil and a
-- list of messages ("[2].amount must be ...": the caller prefixes the field name).
function stats.validate_modifiers(list)
	if type(list) ~= "table" then
		return nil, { "must be a list of modifiers, like { { kind = \"stat\", stat = \"strength\", amount = 5 } }" }
	end
	local errors, out = {}, {}
	local function err(msg) errors[#errors + 1] = msg end
	for i in pairs(list) do
		if math.type(i) ~= "integer" or i < 1 or i > #list then
			return nil, { "must be a list (unexpected key " .. tostring(i) .. ")" }
		end
	end
	for i, m in ipairs(list) do
		local at = "[" .. i .. "]"
		if type(m) ~= "table" then
			err(at .. " must be a table like { kind = \"stat\", stat = \"strength\", amount = 5 }")
		elseif m.kind ~= "stat" then
			err(at .. ".kind must be one of stat (got " .. tostring(m.kind) .. ")")
		else
			if not STAT_SET[m.stat] then err(at .. ".stat must be one of " .. table.concat(stats.STATS, ", ")) end
			local n = math.type(m.amount) == "float" and math.tointeger(m.amount) or m.amount
			if math.type(n) ~= "integer" or n < stats.AMOUNT.min or n > stats.AMOUNT.max then
				err(at .. (m.amount == nil and ": missing amount" or
					(".amount must be an integer from %d to %d"):format(stats.AMOUNT.min, stats.AMOUNT.max)))
			end
			local extra = {}
			for k in pairs(m) do
				if k ~= "kind" and k ~= "stat" and k ~= "amount" then extra[#extra + 1] = tostring(k) end
			end
			table.sort(extra)
			for _, k in ipairs(extra) do err(at .. ": unknown parameter '" .. k .. "' for stat") end
			out[i] = { kind = "stat", stat = m.stat, amount = n }
		end
	end
	if #errors > 0 then return nil, errors end
	return out
end

-- Stored text of a list of modifiers: "stat stat=strength amount=50; stat stat=maxhp amount=-50".
function stats.encode_modifiers(list)
	local parts = {}
	for _, m in ipairs(list) do
		parts[#parts + 1] = "stat stat=" .. tostring(m.stat) .. " amount=" .. tostring(m.amount)
	end
	return table.concat(parts, "; ")
end

-- The list stored by encode_modifiers().
function stats.decode_modifiers(text)
	local list = {}
	for part in tostring(text or ""):gmatch("[^;]+") do
		local m
		for word in part:gmatch("%S+") do
			if not m then
				m = { kind = word }
			else
				local k, v = word:match("^([%w_]+)=(.*)$")
				if k then m[k] = math.tointeger(tonumber(v)) or v end
			end
		end
		if m then list[#list + 1] = m end
	end
	return list
end

-- Sum of the stat modifiers in `list`: { maxhp = 10, strength = -5, ... } (absent = 0).
function stats.modifiers(list)
	local sum = {}
	for _, m in ipairs(list) do
		if m.kind == "stat" and STAT_SET[m.stat] and math.type(m.amount) == "integer" then
			sum[m.stat] = (sum[m.stat] or 0) + m.amount
		end
	end
	return sum
end

return stats
