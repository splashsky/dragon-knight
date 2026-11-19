-- tests/lua/fight_original.lua :: a frozen copy of the fight as shipped in 2.1.0 (commit
-- 3b9dc75): the dice of app/fight/combat.lua (start, run_chance, attack, monster_turn) and
-- the turn structure of app/routes/fight.lua fight(), on the users row copy that held the
-- fight then (currentmonsterhp, currentmonstersleep, currentmonsterimmune,
-- currentuberdamage, currentuberdefense). Spells and items run through `cast` (the test
-- passes the frozen effects engine, tests/lua/effects_original.lua, proven equivalent to
-- the 2.1 content files by test_action.lua). tests/lua/test_round.lua plays the same
-- fights through it and through the round pipeline (app/fight/round.lua) and compares
-- the rolls, messages and state. Do not edit.
local php = require("lib.php")

local original = {}

local sqrt = math.sqrt

-- combat.start
function original.start(st, monster, rand)
	st.currentmonster = monster.id
	st.currentmonsterhp = rand((monster.maxhp / 5) * 4, monster.maxhp)
	st.currentmonstersleep = 0
	st.currentmonsterimmune = monster.immune
	st.currentuberdamage = 0
	st.currentuberdefense = 0
	local chance = rand(1, 10) + php.ceil(sqrt(st.dexterity))
	return chance > (rand(1, 7) + php.ceil(sqrt(monster.maxdam)))
end

-- combat.run_chance
function original.run_chance(st, monster, rand)
	local chance = rand(4, 10) + php.ceil(sqrt(st.dexterity))
	return chance > (rand(1, 5) + php.ceil(sqrt(monster.maxdam)))
end

-- combat.monster_turn
function original.monster_turn(st, monster, rand, after_spell)
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

-- combat.attack
function original.attack(st, monster, rand)
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

-- One request of routes/fight.lua fight() after the monster was picked (and started, for a
-- new encounter): a = { kind = "run" | "attack" | "spell" | "item" | "ambush" } (ambush:
-- the monster swung first). cast(st, a) runs a spell or item: { lines, killed } or
-- { refused }. Returns { yourturn, monsterturn, refused, escaped, victory, died }; `st`
-- changes in place (as the route then saved it).
function original.round(st, monster, a, rand, cast)
	local out = { yourturn = {}, monsterturn = {} }
	if a.kind == "run" then
		if original.run_chance(st, monster, rand) then
			out.escaped = true
			return out
		end
		out.yourturn = { "You tried to run away, but were blocked in front!" }
		out.monsterturn, out.died = original.monster_turn(st, monster, rand, false)
	elseif a.kind == "attack" then
		local lines, killed = original.attack(st, monster, rand)
		out.yourturn = lines
		if killed then
			out.victory = true
			return out
		end
		out.monsterturn, out.died = original.monster_turn(st, monster, rand, false)
	elseif a.kind == "spell" or a.kind == "item" then
		local r = cast(st, a)
		if r.refused then return { refused = r.refused } end
		out.yourturn = r.lines
		if r.killed then
			out.victory = true
			return out
		end
		out.monsterturn, out.died = original.monster_turn(st, monster, rand, true)
	else
		out.yourturn = { "The monster attacks before you are ready!" }
		out.monsterturn, out.died = original.monster_turn(st, monster, rand, false)
	end
	return out
end

return original
