-- app/content/monsters/dark_scorpion.lua :: the Dark Scorpion (the original game's monster 41).
return {
	name = "Dark Scorpion",
	lore = [[
A scorpion as black as burnt wood, hiding under stones in the dry hills past Narcissa. Its sting
is strong enough to numb an arm for a day, and it will stab at anything that comes near its rock.
Miners give them a wide berth, and most of them learn that only once.]],
	level = 15,
	maxhp = 48, maxdam = 40, armor = 26,
	maxexp = 95, maxgold = 32,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 52,
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
