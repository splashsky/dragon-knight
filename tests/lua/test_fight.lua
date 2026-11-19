-- Unit tests for app/fight/combat.lua: scripted dice, outcomes computed by hand from
-- the original fight.php. The fake rand applies PHP's argument casting (truncate, swap) and
-- records the (min, max) it was called with, so tests also pin the exact legacy rolls.
local combat = require("fight.combat")
local php = require("lib.php")
local T = {}

-- rand that returns `values` in order and records the PHP-cast ranges.
local function dice(values)
	local d = { calls = {} }
	local i = 0
	d.rand = function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		i = i + 1
		local v = values[i]
		assert(v ~= nil, "unexpected roll #" .. i .. " rand(" .. a .. "," .. b .. ")")
		assert(v >= a and v <= b, ("roll #%d: %d outside rand(%d,%d)"):format(i, v, a, b))
		d.calls[i] = a .. "," .. b
		return v
	end
	d.done = function() assert(i == #values, ("used %d of %d rolls"):format(i, #values)) end
	return d
end

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function ranges(d, list) eq(table.concat(d.calls, " "), list, "rand ranges") end

local function player(over)
	local p = {
		id = 1, level = 1, charclass = 1, experience = 0, gold = 100,
		currenthp = 15, maxhp = 15, currentmp = 0, maxmp = 0, currenttp = 10, maxtp = 10,
		strength = 5, dexterity = 5, attackpower = 5, defensepower = 5,
		expbonus = 0, goldbonus = 0, spells = "0", latitude = 0, longitude = 0,
		currentfight = 1, currentmonster = 0, currentmonsterhp = 0, currentmonstersleep = 0,
		currentmonsterimmune = 0, currentuberdamage = 0, currentuberdefense = 0, dropcode = 0,
	}
	for k, v in pairs(over or {}) do p[k] = v end
	return p
end

-- seed rows
local BLUE_SLIME = { id = 1, name = "Blue Slime", maxhp = 4, maxdam = 3, armor = 1, level = 1, maxexp = 1, maxgold = 1, immune = 0 }
local CREATURE = { id = 4, name = "Creature", maxhp = 10, maxdam = 8, armor = 2, level = 2, maxexp = 4, maxgold = 2, immune = 0 }
local SHADOW = { id = 5, name = "Shadow", maxhp = 10, maxdam = 9, armor = 3, level = 2, maxexp = 6, maxgold = 2, immune = 1 }

function T.monster_level_band()
	local function band(lat, lon) local a, b = combat.monster_levels(lat, lon); return a .. "-" .. b end
	eq(band(0, 0), "1-1")      -- floor(5/5) = 1
	eq(band(4, -4), "1-1")     -- floor(9/5) = 1
	eq(band(-5, 2), "1-2")     -- floor(10/5) = 2
	eq(band(3, -14), "1-3")    -- floor(19/5) = 3
	eq(band(-50, 7), "9-11")   -- floor(55/5) = 11
end

function T.start_monster_hp_and_swing_first()
	-- Creature: rand(8, 10) -> 9 HP, unscaled.
	-- swing: rand(1,10)=2 + ceil(sqrt(5))=3 -> 5  vs  rand(1,7)=3 + ceil(sqrt(8))=3 -> 6: monster first.
	local st, d = player(), dice({ 9, 2, 3 })
	local first = combat.start(st, CREATURE, d.rand)
	d.done(); ranges(d, "8,10 1,10 1,7")
	eq(st.currentmonsterhp, 9, "hp"); eq(math.type(st.currentmonsterhp), "integer", "hp type")
	eq(st.currentmonster, 4); eq(st.currentmonstersleep, 0); eq(st.currentmonsterimmune, 0)
	eq(first, false, "swing first")
	-- 6 vs 6 is not "greater": still the monster. 7 vs 6: player.
	d = dice({ 9, 3, 3 }); eq(combat.start(player(), CREATURE, d.rand), false)
	d = dice({ 9, 4, 3 }); eq(combat.start(player(), CREATURE, d.rand), true)
	-- Blue Slime: (4/5)*4 = 3.2 -> rand(3, 4)
	st, d = player(), dice({ 3, 1, 1 })
	combat.start(st, BLUE_SLIME, d.rand)
	ranges(d, "3,4 1,10 1,7"); eq(st.currentmonsterhp, 3)
	-- immunity copied from the monster
	st, d = player(), dice({ 8, 1, 1 })
	combat.start(st, SHADOW, d.rand); eq(st.currentmonsterimmune, 1)
	-- buffs left over from an earlier fight are cleared
	st = player({ currentuberdamage = 25, currentuberdefense = 10 })
	combat.start(st, SHADOW, dice({ 8, 1, 1 }).rand)
	eq(st.currentuberdamage, 0); eq(st.currentuberdefense, 0)
end

function T.player_attack()
	-- attackpower 5: rand(3.75 -> 3, 5) = 5, ceil(5/3) = 2; no excellent (rand(1,150)=150 > sqrt(5))
	-- Creature armor 2: rand(1.5 -> 1, 2) = 2, ceil(2/3) = 1; dodge rand(1,200)=200 > sqrt(2)
	-- damage 2 - 1 = 1
	local st = player({ currentmonsterhp = 11 })
	local d = dice({ 5, 150, 2, 200 })
	local lines, killed = combat.attack(st, CREATURE, d.rand)
	d.done(); ranges(d, "3,5 1,150 1,2 1,200")
	eq(lines[1], "You attack the monster for 1 damage."); eq(#lines, 1)
	eq(st.currentmonsterhp, 10); eq(killed, false)
	-- excellent hit: roll 2 <= sqrt(5) (2.236): tohit 2*2 = 4, damage 4 - 1 = 3;
	-- uber damage 25%: 3 + ceil(0.75) = 4
	st = player({ currentmonsterhp = 4, currentuberdamage = 25 })
	d = dice({ 5, 2, 2, 200 })
	lines, killed = combat.attack(st, CREATURE, d.rand)
	eq(lines[1], "Excellent hit!"); eq(lines[2], "You attack the monster for 4 damage.")
	eq(st.currentmonsterhp, 0); eq(killed, true)
	-- the monster dodges: roll 1 <= sqrt(2); no damage, uber not applied
	st = player({ currentmonsterhp = 4, currentuberdamage = 25 })
	d = dice({ 5, 150, 1, 1 })
	lines = combat.attack(st, CREATURE, d.rand)
	eq(lines[1], "The monster is dodging. No damage has been scored.")
	eq(lines[2], "You attack the monster for 0 damage."); eq(st.currentmonsterhp, 4)
	-- damage floor of 1 when the block exceeds the hit
	st = player({ currentmonsterhp = 50, attackpower = 1 })
	d = dice({ 1, 150, 3, 200 })    -- ceil(1/3)=1; armor 3: rand(2,3)=3 -> 1; 1-1=0 -> 1
	combat.attack(st, SHADOW, d.rand); ranges(d, "0,1 1,150 2,3 1,200"); eq(st.currentmonsterhp, 49)
end

function T.monster_turn()
	-- Creature maxdam 8: rand(4, 8) = 8, unscaled
	-- defense 5: rand(3, 5) = 5 -> ceil(5/4) = 2; dodge rand(1,150)=100 > sqrt(5): hit for 6
	local st = player({ currenthp = 15 })
	local d = dice({ 8, 5, 100 })
	local lines, died = combat.monster_turn(st, CREATURE, d.rand, false)
	d.done(); ranges(d, "4,8 3,5 1,150")
	eq(lines[1], "The monster attacks you for 6 damage."); eq(st.currenthp, 9); eq(died, false)
	-- uber defense 50%: 6 - ceil(3) = 3
	st = player({ currenthp = 15, currentuberdefense = 50 })
	d = dice({ 8, 5, 100 })
	combat.monster_turn(st, CREATURE, d.rand, false); eq(st.currenthp, 12)
	-- dodge: roll 2 <= sqrt(5)
	st = player({ currenthp = 3 })
	d = dice({ 8, 5, 2 })
	lines, died = combat.monster_turn(st, CREATURE, d.rand, false)
	eq(lines[1], "You dodge the monster's attack. No damage has been scored.")
	eq(lines[2], "The monster attacks you for 0 damage."); eq(st.currenthp, 3); eq(died, false)
	-- fatal: 8 - 2 = 6 >= 3 hp
	st = player({ currenthp = 3 })
	d = dice({ 8, 5, 100 })
	lines, died = combat.monster_turn(st, CREATURE, d.rand, false)
	eq(st.currenthp, -3); eq(died, true)
	-- block >= hit: damage 1 in both variants; uber defense can't take it below 1
	for _, after_spell in ipairs({ false, true }) do
		st = player({ defensepower = 40, currentuberdefense = 50 })   -- rand(30,40)=40 -> 10
		d = dice({ 2, 40, 100 })                                       -- Blue Slime: rand(1,3)
		combat.monster_turn(st, BLUE_SLIME, d.rand, after_spell)
		ranges(d, "1,3 30,40 1,150"); eq(st.currenthp, 14)
	end
end

function T.monster_sleep_and_wake()
	-- still asleep: rand(1,15)=5 is not > 5: no attack rolls at all
	local st = player({ currentmonstersleep = 5 })
	local d = dice({ 5 })
	local lines = combat.monster_turn(st, CREATURE, d.rand, false)
	d.done(); eq(lines[1], "The monster is still asleep."); eq(#lines, 1); eq(st.currentmonstersleep, 5)
	-- wakes up (6 > 5) and attacks in the same turn
	st = player({ currentmonstersleep = 5 })
	d = dice({ 6, 4, 3, 100 })     -- tohit 4, block ceil(3/4) = 1 -> 3
	lines = combat.monster_turn(st, CREATURE, d.rand, false)
	d.done(); eq(lines[1], "The monster has woken up.")
	eq(lines[2], "The monster attacks you for 3 damage."); eq(st.currentmonstersleep, 0); eq(st.currenthp, 12)
end

function T.spells()
	local heal = { id = 1, name = "Heal", mp = 5, attribute = 10, type = 1 }
	local st = player({ currenthp = 10, maxhp = 15, currentmp = 9 })
	local d = dice({})
	local lines = combat.cast(st, heal, d.rand)
	eq(lines[1], "You have cast the Heal spell, and gained 5 Hit Points.")
	eq(st.currenthp, 15); eq(st.currentmp, 4)

	-- Hurt 15: rand((15/6)*5 = 12.5 -> 12, 15)
	local hurt = { id = 6, name = "Hurt", mp = 5, attribute = 15, type = 2 }
	st = player({ currentmonsterhp = 20, currentmp = 5 })
	d = dice({ 13 })
	local killed
	lines, killed = combat.cast(st, hurt, d.rand)
	ranges(d, "12,15"); eq(lines[1], "You have cast the Hurt spell for 13 damage.")
	eq(st.currentmonsterhp, 7); eq(st.currentmp, 0); eq(killed, false)
	-- Pain 35: (35/6)*5 = 29.166.. -> 29
	st = player({ currentmonsterhp = 20, currentmp = 12 })
	d = dice({ 29 })
	lines, killed = combat.cast(st, { id = 7, name = "Pain", mp = 12, attribute = 35, type = 2 }, d.rand)
	ranges(d, "29,35"); eq(killed, true)
	-- immune (1 or 2) to hurt: no roll, MP still spent
	st = player({ currentmonsterhp = 20, currentmp = 5, currentmonsterimmune = 1 })
	d = dice({})
	lines = combat.cast(st, hurt, d.rand)
	eq(lines[1], "You have cast the Hurt spell, but the monster is immune to it.")
	eq(st.currentmonsterhp, 20); eq(st.currentmp, 0)

	local sleep = { id = 11, name = "Sleep", mp = 10, attribute = 5, type = 3 }
	st = player({ currentmp = 10, currentmonsterimmune = 1 })   -- immune 1 doesn't stop sleep
	lines = combat.cast(st, sleep, dice({}).rand)
	eq(lines[1], "You have cast the Sleep spell. The monster is asleep."); eq(st.currentmonstersleep, 5)
	st = player({ currentmp = 10, currentmonsterimmune = 2 })
	lines = combat.cast(st, sleep, dice({}).rand)
	eq(lines[1], "You have cast the Sleep spell, but the monster is immune to it.")
	eq(st.currentmonstersleep, 0); eq(st.currentmp, 0)

	st = player({ currentmp = 30 })
	lines = combat.cast(st, { id = 15, name = "Rage", mp = 20, attribute = 25, type = 4 }, dice({}).rand)
	eq(lines[1], "You have cast the Rage spell, and will gain 25% damage until the end of this fight.")
	eq(st.currentuberdamage, 25); eq(st.currentmp, 10)
	lines = combat.cast(st, { id = 17, name = "Ward", mp = 10, attribute = 10, type = 5 }, dice({}).rand)
	eq(lines[1], "You have cast the Ward spell, and will gain 10% defense until the end of this fight.")
	eq(st.currentuberdefense, 10); eq(st.currentmp, 0)
end

function T.cast_refusals()
	local heal = { id = 1, name = "Heal", mp = 5, attribute = 10, type = 1 }
	local full = "Your Hit Points are already full. Please go back and try again."
	eq(combat.cast_error(player({ currenthp = 14, maxhp = 15 }), heal), nil)
	eq(combat.cast_error(player({ currenthp = 15, maxhp = 15 }), heal), full)
	eq(combat.cast_error(player({ currenthp = 20, maxhp = 15 }), heal), full)   -- above max (a drop)
	for t = 2, 5 do
		eq(combat.cast_error(player(), { id = 6, name = "X", mp = 5, attribute = 15, type = t }), nil)
	end
	for _, t in ipairs({ 0, 6, 99 }) do
		eq(combat.cast_error(player(), { id = 20, name = "Odd", mp = 5, attribute = 1, type = t }),
			"This spell cannot be cast. Please go back and try again.")
	end
end

function T.run_chance()
	-- rand(4,10)=4 + 3 = 7 vs rand(1,5)=4 + ceil(sqrt(8)) 3 = 7: blocked; 5 + 3 = 8 > 7: escape
	local d = dice({ 4, 4 })
	eq(combat.run_chance(player(), CREATURE, d.rand), false); ranges(d, "4,10 1,5")
	eq(combat.run_chance(player(), CREATURE, dice({ 5, 4 }).rand), true)
end

function T.death_penalty()
	local d = combat.death(player({ gold = 101, maxhp = 15 }))
	eq(d.gold, 51); eq(d.currenthp, 4)
end

function T.victory_rewards()
	-- Creature maxexp 4: (4/6)*5 = 3.33 -> rand(3,4) = 4, unscaled
	-- maxgold 2: (2/6)*5 = 1.66 -> rand(1,2) = 2
	local d = dice({ 4, 2 })
	local r = combat.rewards(player(), CREATURE, d.rand)
	d.done(); ranges(d, "3,4 1,2")
	eq(r.exp, 4); eq(r.gold, 2); eq(r.newexp, 4); eq(r.newgold, 102); eq(r.warnexp, ""); eq(r.warngold, "")
	-- Blue Slime maxexp 1: (1/6)*5 = 0.83 -> rand(0,1) = 0 -> at least 1
	-- bonuses: exp 1 + ceil(0.1*1) = 2; gold 1 + ceil(0.1*1) = 2
	d = dice({ 0, 0 })
	r = combat.rewards(player({ expbonus = 10, goldbonus = 10 }), BLUE_SLIME, d.rand)
	ranges(d, "0,1 0,1"); eq(r.exp, 2); eq(r.gold, 2)
	-- the gold bonus is a % of the gold (legacy: of the exp, 2 + ceil(0.5*4) = 4)
	r = combat.rewards(player({ goldbonus = 50 }), CREATURE, dice({ 4, 2 }).rand)
	eq(r.exp, 4); eq(r.gold, 3)
	r = combat.rewards(player({ goldbonus = -50 }), CREATURE, dice({ 4, 2 }).rand)
	eq(r.gold, 1)
	-- caps
	r = combat.rewards(player({ experience = 16777214, gold = 16777214 }), CREATURE, dice({ 4, 2 }).rand)
	eq(r.exp, 0); eq(r.newexp, 16777214); eq(r.warnexp, "You have maxed out your experience points.")
	eq(r.gold, 0); eq(r.newgold, 16777214); eq(r.warngold, "You have maxed out your gold.")
	r = combat.rewards(player({ experience = 16777210 }), CREATURE, dice({ 4, 2 }).rand)
	eq(r.newexp, 16777214)
end

function T.level_up()
	-- seed levels rows 2-4, class 1: exp 15/45/105, hp 2/3/3, mp 5/4/3, tp 1/2/2,
	-- str 0/1/1, dex 1/2/2, spells 1/0/6
	local rows = {
		[2] = { id = 2, ["1_exp"] = 15, ["1_hp"] = 2, ["1_mp"] = 5, ["1_tp"] = 1,
						["1_strength"] = 0, ["1_dexterity"] = 1, ["1_spells"] = 1 },
		[3] = { id = 3, ["1_exp"] = 45, ["1_hp"] = 3, ["1_mp"] = 4, ["1_tp"] = 2,
						["1_strength"] = 1, ["1_dexterity"] = 2, ["1_spells"] = 0 },
		[4] = { id = 4, ["1_exp"] = 105, ["1_hp"] = 3, ["1_mp"] = 3, ["1_tp"] = 2,
						["1_strength"] = 1, ["1_dexterity"] = 2, ["1_spells"] = 6 },
	}
	local row = function(n) return rows[n] end
	local key = function(stat) return "1_" .. stat end
	local u = player()
	eq(combat.level_up(u, 14, key, row), nil)
	local g = combat.level_up(u, 15, key, row)
	eq(g.level, 2); eq(g.levels, 1); eq(g.hp, 2); eq(g.mp, 5); eq(g.learned, 1)
	eq(g.maxhp, 17); eq(g.maxmp, 5); eq(g.maxtp, 11)
	eq(g.newstrength, 5); eq(g.newdexterity, 6); eq(g.attackpower, 5); eq(g.defensepower, 6)
	eq(g.spells, "0,1")
	-- several levels at once: 2 and 3 (44 < 45 stops at 2; 104 < 105 stops at 3)
	eq(combat.level_up(u, 44, key, row).level, 2)
	g = combat.level_up(u, 104, key, row)
	eq(g.level, 3); eq(g.levels, 2); eq(g.hp, 5); eq(g.mp, 9); eq(g.tp, 3)
	eq(g.strength, 1); eq(g.dexterity, 3); eq(g.learned, 1); eq(g.spells, "0,1")
	eq(g.maxhp, 20); eq(g.maxmp, 9); eq(g.maxtp, 13); eq(g.newstrength, 6); eq(g.newdexterity, 8)
	eq(g.attackpower, 6); eq(g.defensepower, 8)
	-- all the way, stopping where the rows run out
	g = combat.level_up(u, 10 ^ 6, key, row)
	eq(g.level, 4); eq(g.levels, 3); eq(g.learned, 2); eq(g.spells, "0,1,6")
	-- from level 3 only row 4 counts
	g = combat.level_up(player({ level = 3, spells = "0,1" }), 10 ^ 6, key, row)
	eq(g.level, 4); eq(g.levels, 1); eq(g.hp, 3); eq(g.spells, "0,1,6")
	-- no spell learned: spells stays nil
	rows[2]["1_spells"] = 0
	g = combat.level_up(u, 15, key, row)
	eq(g.spells, nil); eq(g.learned, 0)
	-- stops at the max level (100), even with a row 101
	local any = { id = 0, ["1_exp"] = 0, ["1_hp"] = 1, ["1_mp"] = 0, ["1_tp"] = 0,
								["1_strength"] = 0, ["1_dexterity"] = 0, ["1_spells"] = 0 }
	local every = function(n) local r = {}; for k, v in pairs(any) do r[k] = v end; r.id = n; return r end
	g = combat.level_up(player({ level = 97 }), 10 ^ 7, key, every)
	eq(g.level, 100); eq(g.levels, 3); eq(g.hp, 3)
	eq(combat.level_up(player({ level = 100 }), 10 ^ 7, key, every), nil)
	eq(combat.level_up(u, 15, key, function() return nil end), nil)
end

function T.drop_roll_and_pick()
	eq(combat.drop_roll(dice({ 1 }).rand), true)
	eq(combat.drop_roll(dice({ 2 }).rand), false)
	local d = dice({ 3 })
	eq(combat.pick({ "a", "b", "c" }, d.rand), "c"); ranges(d, "1,3")
	eq(combat.pick({}, dice({}).rand), nil)
end

function T.equip_drop()
	local pebble = { id = 1, name = "Life Pebble", attribute1 = "maxhp,10", attribute2 = "X" }
	local sin = { id = 13, name = "Demon's Sin", attribute1 = "maxhp,-50", attribute2 = "strength,50" }
	local wing = { id = 12, name = "Dragon's Wing", attribute1 = "dexterity,50", attribute2 = "X" }
	-- empty slot
	local st = player({ currenthp = 15, maxhp = 15 })
	combat.equip_drop(st, pebble, nil)
	eq(st.maxhp, 25); eq(st.currenthp, 15)
	-- replace pebble with Demon's Sin: -10 then -50 hp, +50 str and attack; HP clamped
	st = player({ currenthp = 25, maxhp = 25 })
	combat.equip_drop(st, sin, pebble)
	eq(st.maxhp, -35); eq(st.currenthp, -35); eq(st.strength, 55); eq(st.attackpower, 55)
	eq(php.mysql_uint(st.maxhp), 0)
	-- replace Sin with Wing: str/attack back, dex/defense up
	st = player({ maxhp = 100, currenthp = 100, strength = 55, attackpower = 55 })
	combat.equip_drop(st, wing, sin)
	eq(st.maxhp, 150); eq(st.currenthp, 100); eq(st.strength, 5); eq(st.attackpower, 5)
	eq(st.dexterity, 55); eq(st.defensepower, 55)
	-- empty slot with a negative item: clamped too
	st = player({ currenthp = 15, maxhp = 15 })
	combat.equip_drop(st, sin, nil)
	eq(st.maxhp, -35); eq(st.currenthp, -35); eq(php.mysql_uint(st.currenthp), 0)
	st = player({ currenthp = 100, maxhp = 100, currentmp = 30, maxmp = 60 })
	combat.equip_drop(st, { id = 99, name = "Curse", attribute1 = "maxhp,-20", attribute2 = "maxmp,-40" }, nil)
	eq(st.maxhp, 80); eq(st.currenthp, 80); eq(st.maxmp, 20); eq(st.currentmp, 20)
end

function T.drop_attribute_text()
	local a = combat.drop_attributes({ attribute1 = "maxhp,-50", attribute2 = "strength,50" })
	eq(a[1], "Max HP-50"); eq(a[2], "Strength +50")
	a = combat.drop_attributes({ attribute1 = "goldbonus,10", attribute2 = "X" })
	eq(#a, 1); eq(a[1], "Gold Bonus +10")
end

return T
