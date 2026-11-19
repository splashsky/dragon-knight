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
local effects = require("lib.effects")

local stats = {}

stats.STATS = effects.STATS

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
		for stat, n in pairs(effects.modifiers(it.modifiers or {})) do add(stat, n) end
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
-- the effects engine use (the original game's users columns): maxhp, maxmp, maxtp,
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

return stats
