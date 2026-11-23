-- Unit tests for app/fight/combat.lua and the turns of a round (fight/round.lua with the
-- spell and item content files, on the fight model: tests/lua/fight_model.lua maps the
-- original game's columns to it): scripted dice, outcomes computed by hand from the
-- original fight.php (level-up thresholds and TP/HP bonuses: lib/leveling.lua). The fake
-- rand applies PHP's argument casting (truncate, swap) and records the (min, max) it was
-- called with, so tests also pin the exact legacy rolls.
local act = require("fight.act")
local combat = require("fight.combat")
local fm = require("tests.fight_model")
local items = require("lib.items")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")
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

-- a spells row (lib/spells.lua) of a content file, with changed fields (as overrides would)
local function spell(key, over)
	local s = assert(spells.get(dk.db:value("SELECT id FROM spells WHERE key = ?", key)), key)
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

-- seed rows
local BLUE_SLIME = { id = 1, name = "Blue Slime", maxhp = 4, maxdam = 3, armor = 1, level = 1, maxexp = 1, maxgold = 1 }
local CREATURE = { id = 4, name = "Creature", maxhp = 10, maxdam = 8, armor = 2, level = 2, maxexp = 4, maxgold = 2 }
local SHADOW = { id = 5, name = "Shadow", maxhp = 10, maxdam = 9, armor = 3, level = 2, maxexp = 6, maxgold = 2, resist = { arcane = 100 } }

function T.monster_level_band()
	local function band(lat, lon) local a, b = combat.monster_levels(lat, lon); return a .. "-" .. b end
	eq(band(0, 0), "1-1")      -- floor(5/5) = 1
	eq(band(4, -4), "1-1")     -- floor(9/5) = 1
	eq(band(-5, 2), "1-2")     -- floor(10/5) = 2
	eq(band(3, -14), "1-3")    -- floor(19/5) = 3
	eq(band(-50, 7), "9-11")   -- floor(55/5) = 11
end

-- A new encounter (fight/round.lua round.start) on old-style row st: monster HP, then who
-- swings first; st gets the fight's columns.
local function start(st, monster, rand)
	local f = state.new({ user_id = 1, round = 1, st = st })
	f.rand = rand
	state.add_monster(f, monster, 1)
	local first = round.start(f)
	for k, v in pairs(fm.flat(f)) do st[k] = v end
	return first
end

function T.start_monster_hp_and_swing_first()
	-- Creature: rand(8, 10) -> 9 HP, unscaled.
	-- swing: rand(1,10)=2 + ceil(sqrt(5))=3 -> 5  vs  rand(1,7)=3 + ceil(sqrt(8))=3 -> 6: monster first.
	local st, d = player(), dice({ 9, 2, 3 })
	local first = start(st, CREATURE, d.rand)
	d.done(); ranges(d, "8,10 1,10 1,7")
	eq(st.currentmonsterhp, 9, "hp"); eq(math.type(st.currentmonsterhp), "integer", "hp type")
	eq(st.currentmonster, 4); eq(st.currentmonstersleep, 0); eq(st.currentmonsterimmune, 0)
	eq(first, false, "swing first")
	-- 6 vs 6 is not "greater": still the monster. 7 vs 6: player.
	d = dice({ 9, 3, 3 }); eq(start(player(), CREATURE, d.rand), false)
	d = dice({ 9, 4, 3 }); eq(start(player(), CREATURE, d.rand), true)
	-- Blue Slime: (4/5)*4 = 3.2 -> rand(3, 4)
	st, d = player(), dice({ 3, 1, 1 })
	start(st, BLUE_SLIME, d.rand)
	ranges(d, "3,4 1,10 1,7"); eq(st.currentmonsterhp, 3)
	-- immunity copied from the monster
	st, d = player(), dice({ 8, 1, 1 })
	start(st, SHADOW, d.rand); eq(st.currentmonsterimmune, 1)
	-- a new fight has no buffs (the statuses of an earlier fight ended with it)
	st = player({ currentuberdamage = 25, currentuberdefense = 10 })
	start(st, SHADOW, dice({ 8, 1, 1 }).rand)
	eq(st.currentuberdamage, 0); eq(st.currentuberdefense, 0)
end

-- One round (fight/round.lua) on old-style row st against `monster`: the player's action
-- a. Returns the round (its lines: r.player, r.enemies); st gets the result.
local function play(st, monster, a, rand)
	local f = fm.model(st, monster, rand)
	local r = round.play(f, a)
	if r.f then
		for k, v in pairs(fm.flat(r.f)) do st[k] = v end
	end
	return r
end

-- The player's attack alone (fight/act.lua): lines, killed.
local function attack(st, monster, rand)
	local f = fm.model(st, monster, rand)
	f.out = {}
	act.run(f, { kind = "attack" })
	for k, v in pairs(fm.flat(f)) do st[k] = v end
	return f.out, st.currentmonsterhp <= 0
end

function T.player_attack()
	-- attackpower 5: rand(3.75 -> 3, 5) = 5, ceil(5/3) = 2; no excellent (rand(1,150)=150 > sqrt(5))
	-- Creature armor 2: rand(1.5 -> 1, 2) = 2, ceil(2/3) = 1; dodge rand(1,200)=200 > sqrt(2)
	-- damage 2 - 1 = 1
	local st = player({ currentmonsterhp = 11 })
	local d = dice({ 5, 150, 2, 200 })
	local lines, killed = attack(st, CREATURE, d.rand)
	d.done(); ranges(d, "3,5 1,150 1,2 1,200")
	eq(lines[1], "You attack the monster for 1 damage."); eq(#lines, 1)
	eq(st.currentmonsterhp, 10); eq(killed, false)
	-- excellent hit: roll 2 <= sqrt(5) (2.236): tohit 2*2 = 4, damage 4 - 1 = 3;
	-- uber damage 25%: 3 + ceil(0.75) = 4
	st = player({ currentmonsterhp = 4, currentuberdamage = 25 })
	d = dice({ 5, 2, 2, 200 })
	lines, killed = attack(st, CREATURE, d.rand)
	eq(lines[1], "Excellent hit!"); eq(lines[2], "You attack the monster for 4 damage.")
	eq(st.currentmonsterhp, 0); eq(killed, true)
	-- the monster dodges: roll 1 <= sqrt(2); no damage, uber not applied
	st = player({ currentmonsterhp = 4, currentuberdamage = 25 })
	d = dice({ 5, 150, 1, 1 })
	lines = attack(st, CREATURE, d.rand)
	eq(lines[1], "The monster is dodging. No damage has been scored.")
	eq(lines[2], "You attack the monster for 0 damage."); eq(st.currentmonsterhp, 4)
	-- damage floor of 1 when the block exceeds the hit
	st = player({ currentmonsterhp = 50, attackpower = 1 })
	d = dice({ 1, 150, 3, 200 })    -- ceil(1/3)=1; armor 3: rand(2,3)=3 -> 1; 1-1=0 -> 1
	attack(st, SHADOW, d.rand); ranges(d, "0,1 1,150 2,3 1,200"); eq(st.currentmonsterhp, 49)
end

-- The monster's turn: a round in which the player does nothing.
local function monster_turn(st, monster, rand)
	local r = play(st, monster, { kind = "continue" }, rand)
	return r.enemies, r.died == true
end

function T.monster_turn()
	-- Creature maxdam 8: rand(4, 8) = 8, unscaled
	-- defense 5: rand(3, 5) = 5 -> ceil(5/4) = 2; dodge rand(1,150)=100 > sqrt(5): hit for 6
	local st = player({ currenthp = 15, currentmonsterhp = 10 })
	local d = dice({ 8, 5, 100 })
	local lines, died = monster_turn(st, CREATURE, d.rand)
	d.done(); ranges(d, "4,8 3,5 1,150")
	eq(lines[1], "The monster attacks you for 6 damage."); eq(st.currenthp, 9); eq(died, false)
	-- uber defense 50%: 6 - ceil(3) = 3
	st = player({ currenthp = 15, currentuberdefense = 50, currentmonsterhp = 10 })
	d = dice({ 8, 5, 100 })
	monster_turn(st, CREATURE, d.rand); eq(st.currenthp, 12)
	-- dodge: roll 2 <= sqrt(5)
	st = player({ currenthp = 3, currentmonsterhp = 10 })
	d = dice({ 8, 5, 2 })
	lines, died = monster_turn(st, CREATURE, d.rand)
	eq(lines[1], "You dodge the monster's attack. No damage has been scored.")
	eq(lines[2], "The monster attacks you for 0 damage."); eq(st.currenthp, 3); eq(died, false)
	-- fatal: 8 - 2 = 6 >= 3 hp
	st = player({ currenthp = 3, currentmonsterhp = 10 })
	d = dice({ 8, 5, 100 })
	lines, died = monster_turn(st, CREATURE, d.rand)
	eq(st.currenthp, -3); eq(died, true)
	-- block >= hit: damage 1 (after a spell too: the original's two variants agree); uber
	-- defense can't take it below 1
	st = player({ defensepower = 40, currentuberdefense = 50, currentmonsterhp = 10 })   -- rand(30,40)=40 -> 10
	d = dice({ 2, 40, 100 })                                       -- Blue Slime: rand(1,3)
	monster_turn(st, BLUE_SLIME, d.rand)
	ranges(d, "1,3 30,40 1,150"); eq(st.currenthp, 14)
	local lines2 = combat.monster_attack(3, { defense = 40, dexterity = 5, is_player = true }, dice({ 2, 40, 100 }).rand,
		function(dmg) return dmg - php.ceil(dmg * 0.5) end)
	eq(lines2[1], "The monster attacks you for 1 damage.")
end

function T.monster_sleep_and_wake()
	-- asleep: no attack rolls at all in a round (sleep is a status that blocks its turn)
	local st = player({ currentmonstersleep = 5, currentmonsterhp = 10 })
	local d = dice({})
	local lines = monster_turn(st, CREATURE, d.rand)
	d.done(); eq(lines[1], "The Creature is still asleep."); eq(#lines, 1); eq(st.currentmonstersleep, 5)
	-- (3.2) it rolls to wake on the clock's ticks: rand(1,15)=5 is not > 5, 6 is; then it
	-- attacks in the next round
	local f = fm.model(player({ currentmonstersleep = 5, currentmonsterhp = 10 }), CREATURE, nil)
	f.tick, f.deadline = 100, 200
	d = dice({ 5, 6, 4, 3, 100 })     -- then tohit 4, block ceil(3/4) = 1 -> 3
	f.rand = d.rand
	local a = round.advance(f, 101)
	eq(#a.lines, 0, "still asleep: nothing said")
	a = round.advance(a.f, 102)
	eq(a.lines[1][2], "The monster has woken up.")
	local r = round.play(a.f, { kind = "continue" })
	d.done(); eq(r.enemies[1], "The monster attacks you for 3 damage."); eq(r.f.st.currenthp, 12)
end

-- A spell turn (fight/act.lua): lines, killed, or the refusal.
local function cast(st, s, rand)
	local f = fm.model(st, CREATURE, rand)
	f.out = {}
	local r = act.run(f, { kind = "spell", spell = s })
	if r.refused then return r.refused, nil, r end
	for k, v in pairs(fm.flat(f)) do st[k] = v end
	return f.out, st.currentmonsterhp <= 0, r
end

function T.spells()
	local heal = spell("heal")
	local st = player({ currenthp = 10, maxhp = 15, currentmp = 9 })
	local d = dice({})
	local lines = cast(st, heal, d.rand)
	eq(lines[1], "You have cast the Heal spell, and gained 5 Hit Points.")
	eq(st.currenthp, 15); eq(st.currentmp, 4)

	-- Hurt 15: rand((15/6)*5 = 12.5 -> 12, 15)
	local hurt = spell("hurt")
	st = player({ currentmonsterhp = 20, currentmp = 5 })
	d = dice({ 13 })
	local killed
	lines, killed = cast(st, hurt, d.rand)
	ranges(d, "12,15"); eq(lines[1], "You have cast the Hurt spell for 13 damage.")
	eq(st.currentmonsterhp, 7); eq(st.currentmp, 0); eq(killed, false)
	-- Pain 35: (35/6)*5 = 29.166.. -> 29
	st = player({ currentmonsterhp = 20, currentmp = 12 })
	d = dice({ 29 })
	lines, killed = cast(st, spell("pain"), d.rand)
	ranges(d, "29,35"); eq(killed, true)
	-- immune (1 or 2) to hurt: no roll, MP still spent
	st = player({ currentmonsterhp = 20, currentmp = 5, currentmonsterimmune = 1 })
	d = dice({})
	lines = cast(st, hurt, d.rand)
	eq(lines[1], "You have cast the Hurt spell, but the monster is immune to it.")
	eq(st.currentmonsterhp, 20); eq(st.currentmp, 0)
	-- an overridden power changes the roll
	st = player({ currentmonsterhp = 50, currentmp = 5 })
	d = dice({ 20 })
	cast(st, spell("hurt", { power = 24 }), d.rand)
	ranges(d, "20,24"); eq(st.currentmonsterhp, 30)

	local sleep = spell("sleep")
	st = player({ currentmp = 10, currentmonsterimmune = 1 })   -- immune 1 doesn't stop sleep
	lines = cast(st, sleep, dice({}).rand)
	eq(lines[1], "You have cast the Sleep spell. The monster is asleep."); eq(st.currentmonstersleep, 5)
	st = player({ currentmp = 10, currentmonsterimmune = 2 })
	lines = cast(st, sleep, dice({}).rand)
	eq(lines[1], "You have cast the Sleep spell, but the monster is immune to it.")
	eq(st.currentmonstersleep, 0); eq(st.currentmp, 0)

	st = player({ currentmp = 30 })
	lines = cast(st, spell("rage"), dice({}).rand)
	eq(lines[1], "You have cast the Rage spell, and will gain 25% damage until the end of this fight.")
	eq(st.currentuberdamage, 25); eq(st.currentmp, 10)
	lines = cast(st, spell("ward"), dice({}).rand)
	eq(lines[1], "You have cast the Ward spell, and will gain 10% defense until the end of this fight.")
	eq(st.currentuberdefense, 10); eq(st.currentmp, 0)
end

function T.cast_refusals()
	local heal = spell("heal")
	local full = "Your Hit Points are already full. Please go back and try again."
	local function refused(st, s)
		local before = st.currentmp
		local _, _, r = cast(st, s, dice({}).rand)
		if r.refused then eq(st.currentmp, before, "no MP spent") end
		return r.refused
	end
	eq(refused(player({ currenthp = 14, maxhp = 15 }), heal), nil)
	eq(refused(player({ currenthp = 15, maxhp = 15 }), heal), full)
	eq(refused(player({ currenthp = 20, maxhp = 15 }), heal), full)   -- above max (a drop)
	for _, key in ipairs({ "sleep", "craze", "ward" }) do eq(refused(player(), spell(key)), nil) end
	-- not castable in fights, retired (the file and its code are gone) or without a file
	local cannot = "This spell cannot be cast. Please go back and try again."
	eq(refused(player({ currenthp = 1 }), spell("heal", { usable_in = "town" })), cannot)
	eq(refused(player({ currenthp = 1 }), spell("heal", { retired = 1 })), cannot)
	eq(refused(player({ currenthp = 1 }), spell("heal", { key = "gone" })), cannot)
end

function T.run_chance()
	-- rand(4,10)=4 + 3 = 7 vs rand(1,5)=4 + ceil(sqrt(8)) 3 = 7: blocked; 5 + 3 = 8 > 7: escape
	local d = dice({ 4, 4 })
	eq(combat.run_chance(player(), CREATURE, d.rand), false); ranges(d, "4,10 1,5")
	eq(combat.run_chance(player(), CREATURE, dice({ 5, 4 }).rand), true)
end

-- 3.4: a quarter of the gold goes (rounded down), not half
function T.death_penalty()
	local d = combat.death(player({ gold = 101, maxhp = 15 }))
	eq(d.gold, 76); eq(d.currenthp, 4)
	eq(combat.death(player({ gold = 3, maxhp = 15 })).gold, 3, "a few coins kept")
	eq(combat.death(player({ gold = 0, maxhp = 15 })).gold, 0)
end

-- 3.4: the weak monsters pay more: the original's roll times 1 + 3 / (level + 1), rounded,
-- plus 5 - level below level 5; the strong ones about what they did
function T.early_gold()
	eq(combat.gold_for(1, 1), 7); eq(combat.gold_for(1, 2), 9)
	eq(combat.gold_for(2, 2), 7); eq(combat.gold_for(3, 2), 6); eq(combat.gold_for(3, 3), 7)
	eq(combat.gold_for(4, 5), 9); eq(combat.gold_for(5, 7), 11); eq(combat.gold_for(10, 18), 23)
	eq(combat.gold_for(50, 150), 159); eq(combat.gold_for(nil, 1), 7, "no level: the first")
	for level = 1, 100 do
		for _, roll in ipairs({ 1, 5, 40, 300 }) do
			assert(combat.gold_for(level, roll) >= roll, "never less than the roll")
		end
	end
end

function T.victory_rewards()
	-- Creature maxexp 4: (4/6)*5 = 3.33 -> rand(3,4) = 4, unscaled
	-- maxgold 2: (2/6)*5 = 1.66 -> rand(1,2) = 2; level 2: round(2 * 2) + 3 = 7
	local d = dice({ 4, 2 })
	local r = combat.rewards(player(), CREATURE, d.rand)
	d.done(); ranges(d, "3,4 1,2")
	eq(r.exp, 4); eq(r.gold, 7); eq(r.newexp, 4); eq(r.newgold, 107); eq(r.warnexp, ""); eq(r.warngold, "")
	-- Blue Slime maxexp 1: (1/6)*5 = 0.83 -> rand(0,1) = 0 -> at least 1; gold the same: 1, at
	-- level 1 round(2.5) + 4 = 7
	-- bonuses: exp 1 + ceil(0.1*1) = 2; gold 7 + ceil(0.1*7) = 8
	d = dice({ 0, 0 })
	r = combat.rewards(player({ expbonus = 10, goldbonus = 10 }), BLUE_SLIME, d.rand)
	ranges(d, "0,1 0,1"); eq(r.exp, 2); eq(r.gold, 8)
	-- the gold bonus is a % of the gold (legacy: of the exp)
	r = combat.rewards(player({ goldbonus = 50 }), CREATURE, dice({ 4, 2 }).rand)
	eq(r.exp, 4); eq(r.gold, 11)
	r = combat.rewards(player({ goldbonus = -50 }), CREATURE, dice({ 4, 2 }).rand)
	eq(r.gold, 4)
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

-- Using a consumable (fight/act.lua with the item's content file).
function T.use_item()
	local function use(st, it, rand)
		local f = fm.model(st, CREATURE, rand)
		f.out = {}
		local r = act.run(f, { kind = "item", item = it })
		if r.refused then return r.refused end
		for k, v in pairs(fm.flat(f)) do st[k] = v end
		return f.out, st.currentmonsterhp <= 0
	end
	local herb = items.by_key("herb")
	local st = player({ currenthp = 5, maxhp = 100, currentmonsterhp = 20 })
	local lines, killed = use(st, herb, dice({}).rand)
	eq(lines[1], "You have used the Herb, and gained 30 Hit Points."); eq(killed, false); eq(st.currenthp, 35)
	-- refusals: full, not a consumable
	eq(use(player({ currenthp = 15, maxhp = 15 }), herb, dice({}).rand),
		"Your Hit Points are already full. Please go back and try again.")
	eq(use(player(), items.by_key("stick"), dice({}).rand), "This item cannot be used. Please go back and try again.")
	-- the Ether restores MP
	st = player({ currentmp = 2, maxmp = 20 })
	lines = use(st, items.by_key("ether"), dice({}).rand)
	eq(lines[1], "You have used the Ether, and gained 18 Magic Points."); eq(st.currentmp, 20)
end

return T
