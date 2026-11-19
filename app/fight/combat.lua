-- fight/combat.lua :: the pure combat math of the original fight.php, ported line by line.
--
-- No DB access here. Every function that rolls dice takes `rand`, a PHP-compatible
-- rand(min, max) (php.rand in production; tests/lua/test_fight.lua injects a scripted
-- one), and is called with exactly the legacy arguments so the distributions match.
-- `st` is a mutable copy of the users row (the legacy in-memory $userrow); messages are
-- returned as lists of plain-text lines (escaped by the templates).
local php = require("lib.php")

local combat = {}

local sqrt = math.sqrt

combat.MAX_EXPERIENCE = 16777215   -- MEDIUMINT UNSIGNED ceiling legacy checked against
combat.MAX_GOLD = 16777215
combat.MAX_LEVEL = 100
combat.MAX_FIGHT = 255             -- users.currentfight was TINYINT UNSIGNED (MySQL clamps)

-- legacy only scales for difficulty 2 and 3; difficulty 1 ignores diff1mod.
local function diffmod(v, difficulty, control)
	if difficulty == 2 then return php.ceil(v * control.diff2mod) end
	if difficulty == 3 then return php.ceil(v * control.diff3mod) end
	return v
end
combat.diffmod = diffmod

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

-- New fight against `monster`: monster HP, sleep, immunity, buffs. Returns true when the
-- player gets to swing first.
function combat.start(st, monster, control, rand)
	st.currentmonster = monster.id
	st.currentmonsterhp = rand((monster.maxhp / 5) * 4, monster.maxhp)
	st.currentmonsterhp = diffmod(st.currentmonsterhp, st.difficulty, control)
	st.currentmonstersleep = 0
	st.currentmonsterimmune = monster.immune
	-- fixed: legacy kept the uber buffs of a fight the player ran from or died in.
	st.currentuberdamage = 0
	st.currentuberdefense = 0
	local chance = rand(1, 10) + php.ceil(sqrt(st.dexterity))
	return chance > (rand(1, 7) + php.ceil(sqrt(monster.maxdam)))
end

-- Run away roll: true when the player escapes cleanly.
function combat.run_chance(st, monster, rand)
	local chance = rand(4, 10) + php.ceil(sqrt(st.dexterity))
	return chance > (rand(1, 5) + php.ceil(sqrt(monster.maxdam)))
end

-- The monster's turn. `after_spell` selects the variant legacy used after casting a spell
-- (tohit raised to toblock + 1 instead of clamping the damage; same outcome).
-- Returns lines, player_died.
function combat.monster_turn(st, monster, control, rand, after_spell)
	local lines = {}
	if st.currentmonstersleep ~= 0 then -- Check to wake up.
		if rand(1, 15) > st.currentmonstersleep then
			st.currentmonstersleep = 0
			lines[#lines + 1] = "The monster has woken up."
		else
			lines[#lines + 1] = "The monster is still asleep."
		end
	end
	if st.currentmonstersleep ~= 0 then return lines, false end

	local tohit = php.ceil(rand(monster.maxdam * .5, monster.maxdam))
	tohit = diffmod(tohit, st.difficulty, control)
	local toblock = php.ceil(rand(st.defensepower * .75, st.defensepower) / 4)
	local damage
	if rand(1, 150) <= sqrt(st.dexterity) then
		lines[#lines + 1] = "You dodge the monster's attack. No damage has been scored."
		damage = 0
	else
		if after_spell then
			if tohit <= toblock then tohit = toblock + 1 end
			damage = tohit - toblock
		else
			damage = tohit - toblock
			if damage < 1 then damage = 1 end
		end
		if st.currentuberdefense ~= 0 then
			damage = damage - php.ceil(damage * (st.currentuberdefense / 100))
		end
		if damage < 1 then damage = 1 end
	end
	lines[#lines + 1] = "The monster attacks you for " .. damage .. " damage."
	st.currenthp = st.currenthp - damage
	return lines, st.currenthp <= 0
end

-- The player's melee attack. Returns lines, monster_killed.
function combat.attack(st, monster, rand)
	local lines = {}
	local tohit = php.ceil(rand(st.attackpower * .75, st.attackpower) / 3)
	if rand(1, 150) <= sqrt(st.strength) then
		tohit = tohit * 2
		lines[#lines + 1] = "Excellent hit!"
	end
	local toblock = php.ceil(rand(monster.armor * .75, monster.armor) / 3)
	local damage
	if rand(1, 200) <= sqrt(monster.armor) then
		lines[#lines + 1] = "The monster is dodging. No damage has been scored."
		damage = 0
	else
		damage = tohit - toblock
		if damage < 1 then damage = 1 end
		if st.currentuberdamage ~= 0 then
			damage = damage + php.ceil(damage * (st.currentuberdamage / 100))
		end
	end
	lines[#lines + 1] = "You attack the monster for " .. damage .. " damage."
	st.currentmonsterhp = st.currentmonsterhp - damage
	return lines, st.currentmonsterhp <= 0
end

-- Why `spell` (known and affordable) can't be cast in combat, or nil when it can.
-- fixed: legacy let a heal spell cost MP at full HP (and heal a negative amount above max
-- HP), and spells of an unknown type were a free no-op turn.
function combat.cast_error(st, spell)
	local t = spell.type
	if t == 1 and st.currenthp >= st.maxhp then
		return "Your Hit Points are already full. Please go back and try again."
	end
	if t ~= 1 and t ~= 2 and t ~= 3 and t ~= 4 and t ~= 5 then
		return "This spell cannot be cast. Please go back and try again."
	end
	return nil
end

-- Casting `spell` (a spells row) in combat; the caller has checked it is known and
-- affordable and that combat.cast_error allows it. Returns lines, monster_killed.
function combat.cast(st, spell, rand)
	local lines = {}
	local t, name, attr = spell.type, spell.name, spell.attribute
	if t == 1 then -- Heal spell.
		local newhp = st.currenthp + attr
		if st.maxhp < newhp then
			attr = st.maxhp - st.currenthp
			newhp = st.currenthp + attr
		end
		st.currenthp = newhp
		st.currentmp = st.currentmp - spell.mp
		lines[1] = "You have cast the " .. name .. " spell, and gained " .. attr .. " Hit Points."
	elseif t == 2 then -- Hurt spell.
		if st.currentmonsterimmune == 0 then
			local damage = rand((attr / 6) * 5, attr)
			st.currentmonsterhp = st.currentmonsterhp - damage
			lines[1] = "You have cast the " .. name .. " spell for " .. damage .. " damage."
		else
			lines[1] = "You have cast the " .. name .. " spell, but the monster is immune to it."
		end
		st.currentmp = st.currentmp - spell.mp
	elseif t == 3 then -- Sleep spell.
		if st.currentmonsterimmune ~= 2 then
			st.currentmonstersleep = attr
			lines[1] = "You have cast the " .. name .. " spell. The monster is asleep."
		else
			lines[1] = "You have cast the " .. name .. " spell, but the monster is immune to it."
		end
		st.currentmp = st.currentmp - spell.mp
	elseif t == 4 then -- +Damage spell.
		st.currentuberdamage = attr
		st.currentmp = st.currentmp - spell.mp
		lines[1] = "You have cast the " .. name .. " spell, and will gain " .. attr ..
							 "% damage until the end of this fight."
	elseif t == 5 then -- +Defense spell.
		st.currentuberdefense = attr
		st.currentmp = st.currentmp - spell.mp
		lines[1] = "You have cast the " .. name .. " spell, and will gain " .. attr ..
							 "% defense until the end of this fight."
	end
	return lines, st.currentmonsterhp <= 0
end

-- Death penalty: half the gold (rounded up) and a quarter of max HP (rounded up).
function combat.death(user)
	return { gold = php.ceil(user.gold / 2), currenthp = php.ceil(user.maxhp / 4) }
end

-- Victory rewards. Returns { exp, gold, newexp, newgold, warnexp, warngold }.
function combat.rewards(user, monster, control, rand)
	local exp = rand((monster.maxexp / 6) * 5, monster.maxexp)
	if exp < 1 then exp = 1 end
	exp = diffmod(exp, user.difficulty, control)
	if user.expbonus ~= 0 then exp = exp + php.ceil((user.expbonus / 100) * exp) end
	local gold = rand((monster.maxgold / 6) * 5, monster.maxgold)
	if gold < 1 then gold = 1 end
	gold = diffmod(gold, user.difficulty, control)
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
-- next levels row (`level_row(n)`, may return nil), up to MAX_LEVEL. Returns nil (no level
-- gained) or the summed gains (hp, mp, tp, strength, dexterity), `levels` (how many),
-- `learned` (spells learned) and the new stats. `key(stat)` maps a stat to the levels
-- column for the user's class (game.level_key).
-- fixed: legacy granted at most one level per victory.
function combat.level_up(user, newexp, key, level_row)
	local g = {
		level = user.level, levels = 0, learned = 0,
		hp = 0, mp = 0, tp = 0, strength = 0, dexterity = 0,
	}
	local spells = user.spells
	-- fixed: legacy left every column unset (and MySQL stored 0) for level >= 100 or a
	-- missing levels row, wiping the character; those victories now just don't level.
	while g.level < combat.MAX_LEVEL do
		local row = level_row(g.level + 1)
		if not row or newexp < row[key("exp")] then break end
		g.level = row.id
		g.levels = g.levels + 1
		g.hp = g.hp + row[key("hp")]
		g.mp = g.mp + row[key("mp")]
		g.tp = g.tp + row[key("tp")]
		g.strength = g.strength + row[key("strength")]
		g.dexterity = g.dexterity + row[key("dexterity")]
		local spell = row[key("spells")]
		if spell ~= 0 then
			spells = spells .. "," .. spell
			g.learned = g.learned + 1
		end
	end
	if g.levels == 0 then return nil end
	g.maxhp = user.maxhp + g.hp
	g.maxmp = user.maxmp + g.mp
	g.maxtp = user.maxtp + g.tp
	g.newstrength = user.strength + g.strength
	g.newdexterity = user.dexterity + g.dexterity
	g.attackpower = user.attackpower + g.strength
	g.defensepower = user.defensepower + g.dexterity
	if g.learned > 0 then g.spells = spells end
	return g
end

-- Drop chance after a victory without a level up: 1 in 30.
function combat.drop_roll(rand)
	return rand(1, 30) == 1
end

---------------------------------------------------------------------------------------
-- Item drops: drops.attribute1/attribute2 are "stat,value" (or "X" for attribute2).

-- users columns a drop may change (legacy $attributearray), with display names.
combat.DROP_STATS = {
	maxhp = "Max HP", maxmp = "Max MP", maxtp = "Max TP", defensepower = "Defense Power",
	attackpower = "Attack Power", strength = "Strength", dexterity = "Dexterity",
	expbonus = "Experience Bonus", goldbonus = "Gold Bonus",
}
combat.SIGNED_STATS = { expbonus = true, goldbonus = true }

-- "stat,value" -> stat, value. "X" -> "maxhp", 0 (legacy placeholder).
function combat.parse_attribute(attr)
	if attr == "X" then return "maxhp", 0 end
	local parts = php.explode(",", attr)
	local v = tonumber(parts[2]) or php.intval(parts[2])
	return parts[1], math.tointeger(v) or v
end

-- One attribute's effect on `st` (sign = 1 to add, -1 to remove). Strength/dexterity also
-- move attack/defense power. Unknown stat names are ignored (legacy wrote any column).
local function apply(st, stat, value, sign)
	if not combat.DROP_STATS[stat] then return end
	st[stat] = st[stat] + sign * value
	if stat == "strength" then st.attackpower = st.attackpower + sign * value end
	if stat == "dexterity" then st.defensepower = st.defensepower + sign * value end
end

-- Equip `drop` into a slot that holds `old` (a drops row) or nothing (nil).
-- Mutates `st` like legacy drop().
function combat.equip_drop(st, drop, old)
	if old then
		local o1s, o1v = combat.parse_attribute(old.attribute1)
		local o2s, o2v = combat.parse_attribute(old.attribute2)
		apply(st, o1s, o1v, -1)
		apply(st, o2s, o2v, -1)
	end
	local n1s, n1v = combat.parse_attribute(drop.attribute1)
	local n2s, n2v = combat.parse_attribute(drop.attribute2)
	apply(st, n1s, n1v, 1)
	apply(st, n2s, n2v, 1)
	-- fixed: legacy skipped this clamp when the slot was empty (matters for negative items).
	if st.currenthp > st.maxhp then st.currenthp = st.maxhp end
	if st.currentmp > st.maxmp then st.currentmp = st.maxmp end
	if st.currenttp > st.maxtp then st.currenttp = st.maxtp end
end

-- Display lines for a drop's attributes: "Max HP +10", and legacy's "Max HP-50".
function combat.drop_attributes(drop)
	local out = {}
	local function line(attr)
		local stat, value = combat.parse_attribute(attr)
		local label = combat.DROP_STATS[stat] or ""
		if value > 0 then return label .. " +" .. php.str(value) end
		return label .. php.str(value)
	end
	out[1] = line(drop.attribute1)
	if drop.attribute2 ~= "X" then out[2] = line(drop.attribute2) end
	return out
end

return combat
