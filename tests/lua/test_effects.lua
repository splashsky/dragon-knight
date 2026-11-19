-- Unit tests for app/lib/effects.lua: validating effect lists, storing them, refusing and
-- applying them (with the original spells' numbers, rolls and messages), and summing
-- passive modifiers. Dice are scripted like in test_fight.lua.
local effects = require("lib.effects")
local php = require("lib.php")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(list, text)
	for _, s in ipairs(list or {}) do
		if s:find(text, 1, true) then return true end
	end
	error("no message containing '" .. text .. "' in: " .. table.concat(list or {}, " | "), 2)
end

-- rand returning `values` in order, recording the PHP-cast ranges.
local function dice(values)
	local d = { calls = {} }
	local i = 0
	d.rand = function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		i = i + 1
		local v = assert(values[i], "unexpected roll")
		assert(v >= a and v <= b, ("roll %d outside rand(%d,%d)"):format(v, a, b))
		d.calls[i] = a .. "," .. b
		return v
	end
	return d
end

local function player(over)
	local p = {
		currenthp = 10, maxhp = 20, currentmp = 5, maxmp = 10, currenttp = 3, maxtp = 10,
		currentmonsterhp = 50, currentmonstersleep = 0, currentmonsterimmune = 0,
		currentuberdamage = 0, currentuberdefense = 0,
	}
	for k, v in pairs(over or {}) do p[k] = v end
	return p
end

local function ctx(p, over)
	local c = { player = p, in_fight = true, intro = "You have cast the Test spell", rand = dice({}).rand }
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end

function T.validate()
	local list = assert(effects.validate({ { kind = "heal_hp", amount = 10.0 }, { kind = "damage", max = 15, min = 3 } }))
	eq(#list, 2); eq(list[1].amount, 10); eq(math.type(list[1].amount), "integer"); eq(list[2].min, 3)
	assert(effects.validate({ { kind = "damage", max = 15 } }), "min is optional")
	local function errors(l, passive)
		local ok, errs = effects.validate(l, passive)
		assert(not ok, "expected errors")
		return errs
	end
	has(errors({}), "at least one effect")
	has(errors("heal"), "must be a list of effects")
	has(errors({ x = 1 }), "must be a list")
	has(errors({ "heal_hp" }), "[1] must be a table")
	has(errors({ { kind = "fireball", amount = 1 } }), "[1].kind must be one of buff_attack_pct, buff_defense_pct, damage")
	has(errors({ { kind = "heal_hp" } }), "[1]: missing amount")
	has(errors({ { kind = "heal_hp", amount = -1 } }), "[1].amount must be an integer from 0 to 1000000")
	has(errors({ { kind = "sleep", chance = 16 } }), "[1].chance must be an integer from 1 to 15")
	has(errors({ { kind = "heal_hp", amount = 1, max = 3 } }), "[1]: unknown parameter 'max' for heal_hp")
	-- active and passive kinds don't mix
	has(errors({ { kind = "stat", stat = "maxhp", amount = 5 } }), "[1].kind must be one of")
	has(errors({ { kind = "heal_hp", amount = 5 } }, true), "[1].kind must be one of stat")
	-- modifiers: any stat, signed amounts, may be empty
	assert(effects.validate({}, true))
	local mods = assert(effects.validate({ { kind = "stat", stat = "maxhp", amount = -50 },
		{ kind = "stat", stat = "gold_bonus_pct", amount = 10 } }, true))
	eq(mods[1].amount, -50)
	has(errors({ { kind = "stat", stat = "luck", amount = 1 } }, true), "[1].stat must be one of maxhp")
end

function T.storage()
	local list = { { kind = "damage", max = 15, min = 3 }, { kind = "sleep", chance = 5 } }
	eq(effects.encode(list), "damage max=15 min=3; sleep chance=5")
	eq(effects.encode({ { kind = "stat", stat = "maxhp", amount = -50 } }), "stat stat=maxhp amount=-50")
	local back = effects.decode("damage max=15 min=3; sleep chance=5")
	eq(#back, 2); eq(back[1].max, 15); eq(back[1].min, 3); eq(back[2].chance, 5)
	eq(effects.decode("stat stat=maxhp amount=-50")[1].stat, "maxhp")
	eq(effects.decode("stat stat=maxhp amount=-50")[1].amount, -50)
	eq(#effects.decode(""), 0)
	eq(effects.decode("fireball power=9")[1].kind, "fireball")
	local flat = effects.flatten(list, "effects", {})
	eq(flat["effects.1.kind"], "damage"); eq(flat["effects.1.max"], 15); eq(flat["effects.2.chance"], 5)
	eq(effects.encode(effects.unflatten(flat, "effects")), effects.encode(list))
	flat["effects.2.pct"] = 9   -- a parameter the kind doesn't have is ignored
	eq(effects.encode(effects.unflatten(flat, "effects")), effects.encode(list))
end

function T.heals()
	-- the original Heal: gains are capped at max HP, MP/TP the same way
	local p = player({ currenthp = 10, maxhp = 15 })
	local lines, changed = effects.apply({ { kind = "heal_hp", amount = 10 } }, ctx(p))
	eq(lines[1], "You have cast the Test spell, and gained 5 Hit Points."); eq(p.currenthp, 15)
	assert(changed.currenthp)
	p = player({ currenthp = 1, maxhp = 100 })
	effects.apply({ { kind = "heal_hp", amount = 10 } }, ctx(p)); eq(p.currenthp, 11)
	p = player({ currentmp = 5, maxmp = 10, currenttp = 3, maxtp = 4 })
	lines = effects.apply({ { kind = "heal_mp", amount = 30 }, { kind = "heal_tp", amount = 30 } }, ctx(p))
	eq(lines[1], "You have cast the Test spell, and gained 5 Magic Points.")
	eq(lines[2], "You have cast the Test spell, and gained 1 Travel Points.")
	eq(p.currentmp, 10); eq(p.currenttp, 4)
	-- above max (after losing gear) never lowers it
	p = player({ currenthp = 25, maxhp = 20 })
	lines = effects.apply({ { kind = "heal_hp", amount = 10 }, { kind = "damage", max = 6 } },
		ctx(p, { rand = dice({ 5 }).rand }))
	eq(p.currenthp, 25); eq(lines[1], "You have cast the Test spell, and gained 0 Hit Points.")
end

function T.damage()
	-- the original Hurt 15: rand((15/6)*5 = 12.5 -> 12, 15), whatever the armor
	local p = player({ currentmonsterhp = 20 })
	local d = dice({ 13 })
	local lines = effects.apply({ { kind = "damage", max = 15 } }, ctx(p, { rand = d.rand }))
	eq(d.calls[1], "12,15"); eq(lines[1], "You have cast the Test spell for 13 damage."); eq(p.currentmonsterhp, 7)
	-- with a minimum
	d = dice({ 3 })
	effects.apply({ { kind = "damage", max = 15, min = 1 } }, ctx(player(), { rand = d.rand }))
	eq(d.calls[1], "1,15")
	-- immune 1 or 2: no roll
	for _, immune in ipairs({ 1, 2 }) do
		p = player({ currentmonsterhp = 20, currentmonsterimmune = immune })
		lines = effects.apply({ { kind = "damage", max = 15 } }, ctx(p))
		eq(lines[1], "You have cast the Test spell, but the monster is immune to it."); eq(p.currentmonsterhp, 20)
	end
end

function T.sleep_and_buffs()
	local p = player({ currentmonsterimmune = 1 })   -- hurt immunity doesn't stop sleep
	local lines = effects.apply({ { kind = "sleep", chance = 9 } }, ctx(p))
	eq(lines[1], "You have cast the Test spell. The monster is asleep."); eq(p.currentmonstersleep, 9)
	p = player({ currentmonsterimmune = 2 })
	lines = effects.apply({ { kind = "sleep", chance = 9 } }, ctx(p))
	eq(lines[1], "You have cast the Test spell, but the monster is immune to it."); eq(p.currentmonstersleep, 0)
	p = player()
	lines = effects.apply({ { kind = "buff_attack_pct", pct = 25 }, { kind = "buff_defense_pct", pct = 10 } }, ctx(p))
	eq(lines[1], "You have cast the Test spell, and will gain 25% damage until the end of this fight.")
	eq(lines[2], "You have cast the Test spell, and will gain 10% defense until the end of this fight.")
	eq(p.currentuberdamage, 25); eq(p.currentuberdefense, 10)
end

function T.refusal()
	local heal = { { kind = "heal_hp", amount = 10 } }
	eq(effects.refusal(heal, ctx(player({ currenthp = 19, maxhp = 20 }))), nil)
	eq(effects.refusal(heal, ctx(player({ currenthp = 20, maxhp = 20 }))), "hp_full")
	eq(effects.refusal(heal, ctx(player({ currenthp = 30, maxhp = 20 }))), "hp_full")
	eq(effects.refusal({ { kind = "heal_mp", amount = 1 } }, ctx(player({ currentmp = 10 }))), "mp_full")
	eq(effects.refusal({ { kind = "heal_tp", amount = 1 } }, ctx(player({ currenttp = 10 }))), "tp_full")
	-- several heals: refused only when none would restore anything
	local both = { { kind = "heal_hp", amount = 5 }, { kind = "heal_mp", amount = 5 } }
	eq(effects.refusal(both, ctx(player({ currenthp = 20, currentmp = 4 }))), nil)
	eq(effects.refusal(both, ctx(player({ currenthp = 20, currentmp = 10 }))), "hp_full")
	-- a heal with another effect always works
	eq(effects.refusal({ heal[1], { kind = "sleep", chance = 3 } }, ctx(player({ currenthp = 20 }))), nil)
	-- outside fights only town-usable effects
	eq(effects.refusal(heal, ctx(player(), { in_fight = false })), nil)
	eq(effects.refusal({ { kind = "damage", max = 5 } }, ctx(player(), { in_fight = false })), "fight_only")
	eq(effects.refusal({ { kind = "damage", max = 5 } }, ctx(player())), nil)
	-- nothing, unknown, invalid or passive effects can't be used
	eq(effects.refusal({}, ctx(player())), "cannot")
	eq(effects.refusal(effects.decode("fireball power=9"), ctx(player())), "cannot")
	eq(effects.refusal(effects.decode("heal_hp"), ctx(player())), "cannot")
	eq(effects.refusal({ { kind = "stat", stat = "maxhp", amount = 5 } }, ctx(player())), "cannot")
	assert(effects.town_usable(both)); assert(not effects.town_usable({ heal[1], { kind = "damage", max = 1 } }))
end

function T.modifiers_and_labels()
	local sum = effects.modifiers({ { kind = "stat", stat = "maxhp", amount = 10 }, { kind = "stat", stat = "maxhp", amount = -50 },
		{ kind = "stat", stat = "strength", amount = 50 }, { kind = "heal_hp", amount = 5 } })
	eq(sum.maxhp, -40); eq(sum.strength, 50); eq(sum.dexterity, nil)
	eq(effects.label({ kind = "damage", max = 15 }), "Hurt"); eq(effects.attribute({ kind = "damage", max = 15 }), "15")
	eq(effects.attribute({ kind = "damage", max = 15, min = 3 }), "3-15")
	eq(effects.label({ kind = "buff_defense_pct", pct = 10 }), "+Defense (%)")
	eq(effects.attribute({ kind = "stat", stat = "maxhp", amount = 10 }), "maxhp +10")
end

return T
