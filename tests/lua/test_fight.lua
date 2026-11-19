-- Unit tests for app/fight/combat.lua: scripted dice, outcomes computed by hand from
-- the original fight.php (level-up thresholds and TP/HP bonuses: lib/leveling.lua). The
-- fake rand applies PHP's argument casting (truncate, swap) and records the (min, max) it
-- was called with, so tests also pin the exact legacy rolls.
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
		expbonus = 0, goldbonus = 0, latitude = 0, longitude = 0,
		currentfight = 1, currentmonster = 0, currentmonsterhp = 0, currentmonstersleep = 0,
		currentmonsterimmune = 0, currentuberdamage = 0, currentuberdefense = 0, dropcode = 0,
	}
	for k, v in pairs(over or {}) do p[k] = v end
	return p
end

-- a spells row as lib/spells.lua returns it: one effect
local function spell(name, mp, usable_in, kind, param, value)
	return { name = name, mp = mp, usable_in = usable_in, effects = { { kind = kind, [param] = value } } }
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
	local heal = spell("Heal", 5, "both", "heal_hp", "amount", 10)
	local st = player({ currenthp = 10, maxhp = 15, currentmp = 9 })
	local d = dice({})
	local lines = combat.cast(st, heal, d.rand)
	eq(lines[1], "You have cast the Heal spell, and gained 5 Hit Points.")
	eq(st.currenthp, 15); eq(st.currentmp, 4)

	-- Hurt 15: rand((15/6)*5 = 12.5 -> 12, 15)
	local hurt = spell("Hurt", 5, "fight", "damage", "max", 15)
	st = player({ currentmonsterhp = 20, currentmp = 5 })
	d = dice({ 13 })
	local killed
	lines, killed = combat.cast(st, hurt, d.rand)
	ranges(d, "12,15"); eq(lines[1], "You have cast the Hurt spell for 13 damage.")
	eq(st.currentmonsterhp, 7); eq(st.currentmp, 0); eq(killed, false)
	-- Pain 35: (35/6)*5 = 29.166.. -> 29
	st = player({ currentmonsterhp = 20, currentmp = 12 })
	d = dice({ 29 })
	lines, killed = combat.cast(st, spell("Pain", 12, "fight", "damage", "max", 35), d.rand)
	ranges(d, "29,35"); eq(killed, true)
	-- immune (1 or 2) to hurt: no roll, MP still spent
	st = player({ currentmonsterhp = 20, currentmp = 5, currentmonsterimmune = 1 })
	d = dice({})
	lines = combat.cast(st, hurt, d.rand)
	eq(lines[1], "You have cast the Hurt spell, but the monster is immune to it.")
	eq(st.currentmonsterhp, 20); eq(st.currentmp, 0)

	local sleep = spell("Sleep", 10, "fight", "sleep", "chance", 5)
	st = player({ currentmp = 10, currentmonsterimmune = 1 })   -- immune 1 doesn't stop sleep
	lines = combat.cast(st, sleep, dice({}).rand)
	eq(lines[1], "You have cast the Sleep spell. The monster is asleep."); eq(st.currentmonstersleep, 5)
	st = player({ currentmp = 10, currentmonsterimmune = 2 })
	lines = combat.cast(st, sleep, dice({}).rand)
	eq(lines[1], "You have cast the Sleep spell, but the monster is immune to it.")
	eq(st.currentmonstersleep, 0); eq(st.currentmp, 0)

	st = player({ currentmp = 30 })
	lines = combat.cast(st, spell("Rage", 20, "fight", "buff_attack_pct", "pct", 25), dice({}).rand)
	eq(lines[1], "You have cast the Rage spell, and will gain 25% damage until the end of this fight.")
	eq(st.currentuberdamage, 25); eq(st.currentmp, 10)
	lines = combat.cast(st, spell("Ward", 10, "fight", "buff_defense_pct", "pct", 10), dice({}).rand)
	eq(lines[1], "You have cast the Ward spell, and will gain 10% defense until the end of this fight.")
	eq(st.currentuberdefense, 10); eq(st.currentmp, 0)
end

function T.cast_refusals()
	local heal = spell("Heal", 5, "both", "heal_hp", "amount", 10)
	local full = "Your Hit Points are already full. Please go back and try again."
	eq(combat.cast_error(player({ currenthp = 14, maxhp = 15 }), heal), nil)
	eq(combat.cast_error(player({ currenthp = 15, maxhp = 15 }), heal), full)
	eq(combat.cast_error(player({ currenthp = 20, maxhp = 15 }), heal), full)   -- above max (a drop)
	for _, e in ipairs({ { "damage", "max" }, { "sleep", "chance" }, { "buff_attack_pct", "pct" },
											 { "buff_defense_pct", "pct" } }) do
		eq(combat.cast_error(player(), spell("X", 5, "fight", e[1], e[2], 1)), nil)
	end
	-- unknown effects, no effects, a passive effect or a town-only spell: refused
	local cannot = "This spell cannot be cast. Please go back and try again."
	eq(combat.cast_error(player(), spell("Odd", 5, "fight", "fireball", "amount", 1)), cannot)
	eq(combat.cast_error(player(), { name = "Empty", mp = 5, usable_in = "fight", effects = {} }), cannot)
	eq(combat.cast_error(player(), { name = "Ring", mp = 5, usable_in = "fight",
		effects = { { kind = "stat", stat = "maxhp", amount = 5 } } }), cannot)
	eq(combat.cast_error(player({ currenthp = 1 }), spell("Mend", 5, "town", "heal_hp", "amount", 10)), cannot)
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

-- the classes' experience curves (app/content/classes/*.lua: the global stages)
local MAGE = { exp_base = 15, exp_stages = "" }
local WARRIOR = { exp_base = 18, exp_stages = "" }
local PALADIN = { exp_base = 20, exp_stages = "" }

-- The spells a level-up teaches, as "id@level ...".
local function learned(g)
	local out = {}
	for _, s in ipairs(g.spells or {}) do out[#out + 1] = s.id .. "@" .. s.level end
	return table.concat(out, " ")
end

function T.level_up()
	-- seed gains for levels 2-4, Mage (exp 15/45/105 from lib/leveling.lua, tp 1/2/2):
	-- hp 2/3/3, mp 5/4/3, str 0/1/1, dex 1/2/2, spells 1/-/6
	local rows = {
		[2] = { hp = 2, mp = 5, strength = 0, dexterity = 1, spells = { 1 } },
		[3] = { hp = 3, mp = 4, strength = 1, dexterity = 2, spells = {} },
		[4] = { hp = 3, mp = 3, strength = 1, dexterity = 2, spells = { 6 } },
	}
	local row = function(n) return rows[n] end
	local u = player()
	eq(combat.level_up(u, MAGE, 14, row), nil)
	local g = combat.level_up(u, MAGE, 15, row)
	eq(g.level, 2); eq(g.levels, 1); eq(g.hp, 2); eq(g.mp, 5); eq(g.tp, 1); eq(g.learned, 1)
	eq(g.strength, 0); eq(g.dexterity, 1)
	-- gains only: the caller adds them to the base stats (attack/defense are derived)
	eq(g.maxhp, nil); eq(g.attackpower, nil)
	eq(learned(g), "1@2")
	-- several levels at once: 2 and 3 (44 < 45 stops at 2; 104 < 105 stops at 3)
	eq(combat.level_up(u, MAGE, 44, row).level, 2)
	g = combat.level_up(u, MAGE, 104, row)
	eq(g.level, 3); eq(g.levels, 2); eq(g.hp, 5); eq(g.mp, 9); eq(g.tp, 3)
	eq(g.strength, 1); eq(g.dexterity, 3); eq(g.learned, 1); eq(learned(g), "1@2")
	-- all the way, stopping where the rows run out
	g = combat.level_up(u, MAGE, 10 ^ 6, row)
	eq(g.level, 4); eq(g.levels, 3); eq(g.learned, 2); eq(learned(g), "1@2 6@4")
	-- from level 3 only row 4 counts
	g = combat.level_up(player({ level = 3 }), MAGE, 10 ^ 6, row)
	eq(g.level, 4); eq(g.levels, 1); eq(g.hp, 3); eq(learned(g), "6@4")
	-- several spells on one level (content classes may list more than one)
	rows[4].spells = { 6, 11 }
	g = combat.level_up(player({ level = 3 }), MAGE, 10 ^ 6, row)
	eq(g.learned, 2); eq(learned(g), "6@4 11@4")
	-- no spell learned: spells stays nil
	rows[2].spells = {}
	g = combat.level_up(u, MAGE, 15, row)
	eq(g.spells, nil); eq(g.learned, 0)
	rows[2].spells = nil
	g = combat.level_up(u, MAGE, 15, row)
	eq(g.spells, nil); eq(g.learned, 0)
	-- thresholds follow each class's curve: Warrior level 2 at 18, Paladin at 20
	eq(combat.level_up(player({ charclass = 2 }), WARRIOR, 17, row), nil)
	eq(combat.level_up(player({ charclass = 2 }), WARRIOR, 18, row).level, 2)
	eq(combat.level_up(player({ charclass = 3 }), PALADIN, 19, row), nil)
	eq(combat.level_up(player({ charclass = 3 }), PALADIN, 20, row).level, 2)
	-- milestone levels add the HP bonus; TP follows the formula
	local any = { hp = 1, mp = 0, strength = 0, dexterity = 0, spells = {} }
	local every = function() return any end
	g = combat.level_up(player({ level = 9 }), MAGE, 4000, every)   -- Mage level 10 at 1970, 11 at 2991, 12 at 4522
	eq(g.level, 11); eq(g.levels, 2); eq(g.hp, 1 + 10 + 1); eq(g.tp, 2 + 2)
	-- level 99 (+50 HP, +5 TP), then 100 needs the 16777215 cap
	g = combat.level_up(player({ level = 98 }), MAGE, 16777214, every)
	eq(g.level, 99); eq(g.levels, 1); eq(g.hp, 51); eq(g.tp, 5)
	-- stops at the max level (100)
	g = combat.level_up(player({ level = 97 }), MAGE, 10 ^ 8, every)
	eq(g.level, 100); eq(g.levels, 3); eq(g.hp, 1 + 51 + 1); eq(g.tp, 5 + 5 + 0)
	eq(combat.level_up(player({ level = 100 }), MAGE, 10 ^ 8, every), nil)
	eq(combat.level_up(u, MAGE, 15, function() return nil end), nil)
end

function T.drop_roll_and_pick()
	eq(combat.drop_roll(dice({ 1 }).rand), true)
	eq(combat.drop_roll(dice({ 2 }).rand), false)
	local d = dice({ 3 })
	eq(combat.pick({ "a", "b", "c" }, d.rand), "c"); ranges(d, "1,3")
	eq(combat.pick({}, dice({}).rand), nil)
end

-- Using a consumable (combat.use_error / combat.use): an items row with decoded effects.
function T.use_item()
	local herb = { name = "Herb", category = "consumable", use_effects = { { kind = "heal_hp", amount = 30 } } }
	local st = player({ currenthp = 5, maxhp = 100, currentmonsterhp = 20 })
	eq(combat.use_error(st, herb), nil)
	local lines, killed = combat.use(st, herb, dice({}).rand)
	eq(lines[1], "You have used the Herb, and gained 30 Hit Points."); eq(killed, false); eq(st.currenthp, 35)
	-- refusals: full, not a consumable, nothing to do
	eq(combat.use_error(player({ currenthp = 15, maxhp = 15 }), herb),
		"Your Hit Points are already full. Please go back and try again.")
	eq(combat.use_error(player(), { name = "Stick", category = "weapon", use_effects = {} }),
		"This item cannot be used. Please go back and try again.")
	-- a damaging item hurts the monster (rolls like a Hurt spell) and may kill it
	local bomb = { name = "Bomb", category = "consumable", use_effects = { { kind = "damage", max = 12 } } }
	st = player({ currentmonsterhp = 10 })
	local d = dice({ 11 })
	lines, killed = combat.use(st, bomb, d.rand)
	ranges(d, "10,12"); eq(lines[1], "You have used the Bomb for 11 damage."); eq(killed, true)
end

return T
