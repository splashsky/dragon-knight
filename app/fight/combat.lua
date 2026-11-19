-- fight/combat.lua :: the pure combat math of the original fight.php, ported line by line.
--
-- No DB access here. Every function that rolls dice takes `rand`, a PHP-compatible
-- rand(min, max) (php.rand in production; tests/lua/test_fight.lua injects a scripted
-- one), and is called with exactly the legacy arguments so the distributions match.
-- `st` is a mutable copy of the users row with the effective stats under the original
-- column names (game.player: maxhp, strength, attackpower, expbonus, ...; the legacy
-- in-memory $userrow); messages are returned as lists of plain-text lines (escaped by the
-- templates). The round (fight/round.lua) applies the damage; spells and items are
-- scripted content run by fight/act.lua.
local leveling = require("lib.leveling")
local php = require("lib.php")

local combat = {}

local sqrt = math.sqrt

combat.MAX_EXPERIENCE = leveling.MAX_EXPERIENCE   -- MEDIUMINT UNSIGNED ceiling legacy checked against
combat.MAX_GOLD = 16777215
combat.MAX_LEVEL = leveling.MAX_LEVEL

-- Monster level band from the distance to the origin (one mlevel per five spaces).
function combat.monster_levels(latitude, longitude)
	if latitude < 0 then latitude = latitude * -1 end
	if longitude < 0 then longitude = longitude * -1 end
	local maxlevel = php.floor(math.max(latitude + 5, longitude + 5) / 5)
	if maxlevel < 1 then maxlevel = 1 end
	local minlevel = maxlevel - 2
	if minlevel < 1 then minlevel = 1 end
	return minlevel, maxlevel
end

-- ORDER BY RAND() LIMIT 1 over `rows` (uniform pick); nil when empty.
function combat.pick(rows, rand)
	if #rows == 0 then return nil end
	return rows[rand(1, #rows)]
end

-- A monster's HP at the start of an encounter: rand(maxhp * 4/5, maxhp).
function combat.start_hp(monster, rand)
	return rand((monster.maxhp / 5) * 4, monster.maxhp)
end

-- Who swings first in a new encounter: true when the player (dexterity) beats the first
-- monster (its maximum damage).
function combat.swing_first(st, monster, rand)
	local chance = rand(1, 10) + php.ceil(sqrt(st.dexterity))
	return chance > (rand(1, 7) + php.ceil(sqrt(monster.maxdam)))
end

-- Run away roll: true when the player escapes cleanly.
function combat.run_chance(st, monster, rand)
	local chance = rand(4, 10) + php.ceil(sqrt(st.dexterity))
	return chance > (rand(1, 5) + php.ceil(sqrt(monster.maxdam)))
end

-- A monster's attack (`maxdam`: its maximum damage) on `target` (a combatant handle: the
-- player, or an ally in the player's place: defense, dexterity, is_player, name).
-- `modify(damage)` applies the statuses' damage modifiers (fight/engine.lua; the original
-- uber defense buff is one). Returns lines, damage (the caller takes it off the target).
-- legacy: after a spell the original raised tohit to toblock + 1 instead of clamping the
-- damage to 1; the outcome is the same, so there is one formula.
function combat.monster_attack(maxdam, target, rand, modify)
	local lines = {}
	local tohit = php.ceil(rand(maxdam * .5, maxdam))
	local toblock = php.ceil(rand(target.defense * .75, target.defense) / 4)
	local damage
	if rand(1, 150) <= sqrt(target.dexterity) then
		lines[#lines + 1] = target.is_player and "You dodge the monster's attack. No damage has been scored." or
			("Your " .. tostring(target.name) .. " dodges the monster's attack. No damage has been scored.")
		damage = 0
	else
		damage = tohit - toblock
		if damage < 1 then damage = 1 end
		if modify then damage = modify(damage) end
		if damage < 1 then damage = 1 end
	end
	lines[#lines + 1] = target.is_player and ("The monster attacks you for " .. damage .. " damage.") or
		("The monster attacks your " .. tostring(target.name) .. " for " .. damage .. " damage.")
	return lines, damage
end

-- The player's melee attack: `attacker` (attack, strength) on `target` (defense: a
-- monster's armor). `modify(damage)` applies the statuses' damage modifiers (the uber
-- damage buff is one). Returns lines, damage.
function combat.attack(attacker, target, rand, modify)
	local lines = {}
	local tohit = php.ceil(rand(attacker.attack * .75, attacker.attack) / 3)
	if rand(1, 150) <= sqrt(attacker.strength) then
		tohit = tohit * 2
		lines[#lines + 1] = "Excellent hit!"
	end
	local toblock = php.ceil(rand(target.defense * .75, target.defense) / 3)
	local damage
	if rand(1, 200) <= sqrt(target.defense) then
		lines[#lines + 1] = "The monster is dodging. No damage has been scored."
		damage = 0
	else
		damage = tohit - toblock
		if damage < 1 then damage = 1 end
		if modify then damage = modify(damage) end
		if damage < 1 then damage = 1 end
	end
	lines[#lines + 1] = "You attack the monster for " .. damage .. " damage."
	return lines, damage
end

-- Death penalty: half the gold (rounded up) and a quarter of max HP (rounded up).
function combat.death(user)
	return { gold = php.ceil(user.gold / 2), currenthp = php.ceil(user.maxhp / 4) }
end

-- Victory rewards. Returns { exp, gold, newexp, newgold, warnexp, warngold }.
function combat.rewards(user, monster, rand)
	local exp = rand((monster.maxexp / 6) * 5, monster.maxexp)
	if exp < 1 then exp = 1 end
	if user.expbonus ~= 0 then exp = exp + php.ceil((user.expbonus / 100) * exp) end
	local gold = rand((monster.maxgold / 6) * 5, monster.maxgold)
	if gold < 1 then gold = 1 end
	-- fixed: legacy took the gold bonus as a percentage of the experience gained.
	if user.goldbonus ~= 0 then gold = gold + php.ceil((user.goldbonus / 100) * gold) end

	local r = { warnexp = "", warngold = "" }
	if user.experience + exp < combat.MAX_EXPERIENCE then
		r.newexp = user.experience + exp
	else
		r.newexp = user.experience
		exp = 0
		r.warnexp = "You have maxed out your experience points."
	end
	if user.gold + gold < combat.MAX_GOLD then
		r.newgold = user.gold + gold
	else
		r.newgold = user.gold
		gold = 0
		r.warngold = "You have maxed out your gold."
	end
	r.exp, r.gold = exp, gold
	return r
end

-- Level ups for `newexp` experience: one level at a time while the experience covers the
-- next level (leveling.exp_for with the class `cls`'s curve), up to MAX_LEVEL.
-- `gains(level)` returns the class's gains for that level ({ hp, mp, strength, dexterity,
-- spells = { spell id, ... } }, classes.levels; nil stops the loop); TP and the HP
-- milestone bonus are added from lib/leveling.lua. Returns nil (no level gained) or the
-- new `level`, how many `levels`, the summed gains (hp, mp, tp, strength, dexterity: added
-- to the base stats), `learned` (how many spells the schedule taught, known ones included,
-- like legacy) and `spells` ({ { id, level }, ... } or nil).
-- fixed: legacy granted at most one level per victory.
function combat.level_up(user, cls, newexp, gains)
	local g = {
		level = user.level, levels = 0, learned = 0,
		hp = 0, mp = 0, tp = 0, strength = 0, dexterity = 0,
	}
	local learned = {}
	-- fixed: legacy left every column unset (and MySQL stored 0) for level >= 100 or a
	-- missing levels row, wiping the character; those victories now just don't level.
	while g.level < combat.MAX_LEVEL do
		local level = g.level + 1
		local need = leveling.exp_for(cls, level)
		if not need or newexp < need then break end
		local row = gains(level)
		if not row then break end
		g.level = level
		g.levels = g.levels + 1
		g.hp = g.hp + row.hp + leveling.hp_bonus(level)
		g.mp = g.mp + row.mp
		g.tp = g.tp + leveling.tp_gain(level)
		g.strength = g.strength + row.strength
		g.dexterity = g.dexterity + row.dexterity
		for _, spell in ipairs(row.spells or {}) do
			learned[#learned + 1] = { id = spell, level = level }
			g.learned = g.learned + 1
		end
	end
	if g.levels == 0 then return nil end
	if g.learned > 0 then g.spells = learned end
	return g
end

-- Drop chance after a victory without a level up: 1 in 30.
function combat.drop_roll(rand)
	return rand(1, 30) == 1
end

return combat
