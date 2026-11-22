-- app/content/monsters/ultraskeleton.lua :: the Ultraskeleton (the original game's monster 48).
return {
	name = "Ultraskeleton",
	lore = [[
The top of the skeleton line: a bone frame reinforced with iron and banded with old charms,
sometimes found guarding crypts past Gilead. It does not speak, but its armour does, clanking with
every step. Adventurers who have fought one say the second blow is always harder than the first.]],
	icon = "ultraskeleton",
	level = 16,
	maxhp = 52, maxdam = 46, armor = 32,
	maxexp = 116, maxgold = 39,
	immune = 0,
	maxmp = 55,
	speech = {
		start = { "*rattles, iron on bone*", chance = 25 },
		turn = { "*clank*", chance = 15 },
		winning = { "*clank clank*", chance = 20 },
		losing = { "*rattles*", chance = 25 },
		hurt = { "*clangs*", chance = 20 },
		death = { "*falls with a clatter of iron*", chance = 60 },
		victory = { "*rattles*", chance = 25 },
	},
}
