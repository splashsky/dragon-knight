-- app/content/monsters/silver_scorpion.lua :: the Silver Scorpion (the original game's monster 31).
return {
	name = "Silver Scorpion",
	lore = [[
A scorpion with a shell like polished tin, found under the dunes beyond Hambry. Its armour
turns most blades, so the trick is to find the soft place under the tail before it turns
the other way. Dealers in Endworld pay well for an intact shell, which is one of the few
things about the creature that anyone has ever wanted.]],
	icon = "silver_scorpion",
	level = 40,
	maxhp = 30, maxdam = 160, armor = 350,
	maxexp = 63, maxgold = 2000,
	resist = { arcane = 100, neutral = 25, poison = 50, lightning = -50 },  -- immune to arcane (the hurt spells)
	ward = { sleep = 100, poison = 100, venom = 100 },
	attack_element = "poison",
	maxmp = 144,
	speech = {
		start = { "*clicks*", chance = 12 },
		turn = { "*clicks its claws*", chance = 6 },
		winning = { "*hisses*", chance = 8 },
		losing = { "*rattles*", chance = 10 },
		hurt = { "*clicks sharply*", chance = 12 },
		death = { "*a thin, dying hiss*", chance = 40 },
	},
}
