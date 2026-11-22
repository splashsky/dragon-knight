-- Unit tests for lib/stats.lua: derived stats (base + equipped items) and their inverse,
-- and gear's modifiers (validation, storage, sums).
local stats = require("lib.stats")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function base(over)
	local b = { base_maxhp = 15, base_maxmp = 0, base_maxtp = 10, strength = 5, dexterity = 5, base_attack = 0,
		base_defense = 0, base_exp_bonus = 0, base_gold_bonus = 0, currenthp = 15, currentmp = 0, currenttp = 10 }
	for k, v in pairs(over or {}) do b[k] = v end
	return b
end

local function mod(stat, amount) return { kind = "stat", stat = stat, amount = amount } end

-- items rows as lib/items.lua returns them (the fields stats.item_mods reads)
local BLADE = { attack = 250, defense = 0, modifiers = { mod("strength", 50) } }
local RAIMENT = { attack = 0, defense = 200, modifiers = { mod("dexterity", 50) } }
local SIN = { attack = 0, defense = 0, modifiers = { mod("maxhp", -50), mod("strength", 50) } }
local CLAW = { attack = 0, defense = 0, modifiers = { mod("attack", 25) } }
local FORTUNE = { attack = 0, defense = 0, modifiers = { mod("gold_bonus_pct", 10) } }
local DARK_AXE = { attack = 100, defense = 0, modifiers = { mod("exp_bonus_pct", -5) } }

function T.derive_without_gear()
	local s = stats.derive(base(), {})
	eq(s.maxhp, 15); eq(s.maxmp, 0); eq(s.maxtp, 10); eq(s.strength, 5); eq(s.dexterity, 5)
	eq(s.attack, 5, "attack = strength"); eq(s.defense, 5, "defense = dexterity")
	eq(s.exp_bonus_pct, 0); eq(s.gold_bonus_pct, 0)
end

function T.derive_with_gear()
	-- the original shop's numbers: a Destiny Blade adds 250 attack and 50 strength (which
	-- counts toward attack too); a Raiment 200 defense and 50 dexterity
	local mods = stats.item_mods({ BLADE, RAIMENT, CLAW, FORTUNE, DARK_AXE })
	eq(mods.attack, 375); eq(mods.strength, 50); eq(mods.defense, 200); eq(mods.dexterity, 50)
	eq(mods.gold_bonus_pct, 10); eq(mods.exp_bonus_pct, -5)
	local s = stats.derive(base({ strength = 20, dexterity = 10, base_attack = 3 }), mods)
	eq(s.strength, 70); eq(s.dexterity, 60)
	eq(s.attack, 70 + 3 + 375); eq(s.defense, 60 + 200)
	eq(s.exp_bonus_pct, -5); eq(s.gold_bonus_pct, 10)
	-- negative modifiers never take the unsigned stats below 0 (MySQL clamped them)
	s = stats.derive(base({ base_maxhp = 30 }), stats.item_mods({ SIN }))
	eq(s.maxhp, 0); eq(s.strength, 55); eq(s.attack, 55)
	s = stats.derive(base({ strength = 5 }), { strength = -20, attack = 5 })
	eq(s.strength, 0); eq(s.attack, 0, "attack from the raw strength (-15 + 5)")
	-- the bonuses may be negative
	eq(stats.derive(base({ base_exp_bonus = -500 }), {}).exp_bonus_pct, -500)
end

function T.solve_is_the_inverse()
	local mods = stats.item_mods({ BLADE, SIN, CLAW, FORTUNE })
	local expected = { maxhp = 40, maxmp = 10, maxtp = 12, strength = 105, dexterity = 8, attack = 400, defense = 9,
		exp_bonus_pct = 0, gold_bonus_pct = 25 }
	local b = stats.solve(expected, mods)
	eq(b.base_maxhp, 90); eq(b.strength, 5); eq(b.base_gold_bonus, 15)
	-- attack 400 = strength 105 + blade 250 + claw 25 + 20 that is neither
	eq(b.base_attack, 20); eq(b.base_defense, 1)
	eq(#stats.diff(stats.derive(b, mods), expected), 0, "derive(solve(x)) == x")
	-- consistent stored stats give no extra attack/defense
	b = stats.solve({ maxhp = 15, maxmp = 0, maxtp = 10, strength = 55, dexterity = 5, attack = 305, defense = 5,
		exp_bonus_pct = 0, gold_bonus_pct = 0 }, stats.item_mods({ BLADE }))
	eq(b.strength, 5); eq(b.base_attack, 0); eq(b.base_defense, 0)
	eq(table.concat(stats.diff({ maxhp = 1, attack = 2 }, { maxhp = 1, attack = 3 }), ","), "attack")
end

function T.player_and_clamp()
	local u = base({ id = 7, currenthp = 80 })
	local s = stats.derive(u, stats.item_mods({ BLADE }))
	local p = stats.player(u, s)
	eq(p.id, 7); eq(p.maxhp, 15); eq(p.strength, 55); eq(p.attackpower, 305); eq(p.defensepower, 5)
	eq(p.expbonus, 0); eq(p.goldbonus, 0); eq(u.attackpower, nil, "the row itself is untouched")
	local c = stats.clamped(u, s)
	eq(c.currenthp, 15); eq(c.currentmp, 0); eq(c.currenttp, 10)
end

function T.modifiers()
	local list = assert(stats.validate_modifiers({ mod("maxhp", -50), { kind = "stat", stat = "gold_bonus_pct", amount = 10.0 } }))
	eq(list[1].amount, -50); eq(list[2].amount, 10); eq(math.type(list[2].amount), "integer")
	assert(stats.validate_modifiers({}), "may be empty")
	local function errors(l)
		local ok, errs = stats.validate_modifiers(l)
		assert(not ok, "expected errors")
		return table.concat(errs, " | ")
	end
	local function has(s, text) assert(s:find(text, 1, true), "no '" .. text .. "' in " .. s) end
	has(errors("strength"), "must be a list of modifiers")
	has(errors({ x = 1 }), "must be a list (unexpected key x)")
	has(errors({ "maxhp" }), "[1] must be a table")
	has(errors({ { kind = "heal_hp", amount = 5 } }), "[1].kind must be one of stat, resist, ward (got heal_hp)")
	has(errors({ { kind = "stat", stat = "luck", amount = 1 } }), "[1].stat must be one of maxhp, maxmp")
	has(errors({ { kind = "stat", stat = "maxhp" } }), "[1]: missing amount")
	has(errors({ { kind = "stat", stat = "maxhp", amount = 2000000 } }), "[1].amount must be an integer from -1000000 to 1000000")
	has(errors({ { kind = "stat", stat = "maxhp", amount = 1, max = 3 } }), "[1]: unknown parameter 'max' for stat")
	-- stored as text, as schema version 6 wrote it
	local text = stats.encode_modifiers({ mod("maxhp", -50), mod("strength", 50) })
	eq(text, "stat stat=maxhp amount=-50; stat stat=strength amount=50")
	local back = stats.decode_modifiers(text)
	eq(#back, 2); eq(back[1].kind, "stat"); eq(back[1].stat, "maxhp"); eq(back[1].amount, -50); eq(back[2].amount, 50)
	eq(#stats.decode_modifiers(""), 0)
	-- sums (unknown kinds or stats don't count)
	local sum = stats.modifiers({ mod("maxhp", 10), mod("maxhp", -50), mod("strength", 5), { kind = "odd", stat = "maxhp", amount = 1 },
		mod("luck", 3) })
	eq(sum.maxhp, -40); eq(sum.strength, 5); eq(sum.luck, nil); eq(sum.dexterity, nil)
end

-- Resistances and wards (schema version 21): checked, stored and summed like stats, but
-- apart from them.
function T.resistance_and_ward_modifiers()
	local list = assert(stats.validate_modifiers({ { kind = "resist", element = "fire", amount = 25 },
		{ kind = "ward", status = "sleep", amount = 30 }, mod("strength", 5) }))
	eq(list[1].element, "fire"); eq(list[2].status, "sleep"); eq(list[2].amount, 30)
	local function errors(l)
		local ok, errs = stats.validate_modifiers(l)
		assert(not ok, "expected errors")
		return table.concat(errs, " | ")
	end
	local function has(s, text) assert(s:find(text, 1, true), "no '" .. text .. "' in " .. s) end
	has(errors({ { kind = "resist", element = "plasma", amount = 5 } }), "[1].element must be one of neutral, fire,")
	has(errors({ { kind = "resist", element = "fire", amount = 201 } }), "[1].amount must be an integer from -100 to 200")
	has(errors({ { kind = "ward", status = "Sleep!", amount = 5 } }), "[1].status must be the key of a status")
	has(errors({ { kind = "ward", status = "sleep", amount = -1 } }), "[1].amount must be an integer from 0 to 100")
	has(errors({ { kind = "ward", status = "sleep", stat = "maxhp", amount = 5 } }), "[1]: unknown parameter 'stat' for ward")
	local text = stats.encode_modifiers(list)
	eq(text, "resist element=fire amount=25; ward status=sleep amount=30; stat stat=strength amount=5")
	local back = stats.decode_modifiers(text)
	eq(back[1].kind, "resist"); eq(back[1].element, "fire"); eq(back[1].amount, 25); eq(back[2].status, "sleep")
	-- they don't count as stats; stats.affinities sums them over the gear
	eq(stats.modifiers(back).strength, 5); eq(stats.modifiers(back).fire, nil)
	local ring = { modifiers = { { kind = "resist", element = "fire", amount = -10 }, { kind = "ward", status = "sleep", amount = 50 } } }
	local a = stats.affinities({ { modifiers = back }, ring, BLADE })
	eq(a.resist.fire, 15); eq(a.ward.sleep, 80); eq(a.resist.frost, nil)
	local p = stats.player(base({}), { resist = a.resist, ward = a.ward, attack_element = "fire" })
	eq(p.resist.fire, 15); eq(p.ward.sleep, 80); eq(p.attack_element, "fire")
end

return T
