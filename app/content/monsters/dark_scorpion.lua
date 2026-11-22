-- app/content/monsters/dark_scorpion.lua :: the Dark Scorpion (the original game's monster 41).
local function unvenomed(m)
	return not m.target:has_status("venom")
end

return {
	name = "Dark Scorpion",
	lore = [[
A scorpion as black as burnt wood, hiding under stones in the dry hills past Narcissa. Its sting
is strong enough to numb an arm for a day, and it will stab at anything that comes near its rock.
Miners give them a wide berth, and most of them learn that only once.]],
	icon = "dark_scorpion",
	level = 15,
	maxhp = 48, maxdam = 40, armor = 26,
	maxexp = 95, maxgold = 32,
	resist = { arcane = 100, shadow = 50, poison = 75, fire = -25 },   -- no hurt spells
	ward = { poison = 100, venom = 100 },
	attack_element = "poison",
	maxmp = 52,
	spells = {
		-- opens with venom, and again every 3rd turn once it has worn off
		{ spell = "venom", weight = 6, when = function(m)
			return unvenomed(m) and (m.turn == 1 or m.turn % 3 == 0)
		end },
	},
	speech = {
		start = { "*clicks*", chance = 15 },
		turn = { "*hisses*", chance = 15 },
		winning = { "*clicks its claws*", chance = 20 },
		losing = { "*scuttles back*", chance = 25 },
		hurt = { "*hisses sharply*", chance = 25 },
		death = { "*goes still*", chance = 50 },
		victory = { "*clicks*", chance = 20 },
	},
}
