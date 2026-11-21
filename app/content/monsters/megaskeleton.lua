-- app/content/monsters/megaskeleton.lua :: the Megaskeleton (the original game's monster 37).
return {
	name = "Megaskeleton",
	lore = [[
Several skeletons fused together by a careless necromancer, which left it bigger, heavier and a
little confused. It shambles down the old roads near Kalle dragging a cart of bones it has
collected. It has no name, but the bones still remember how to fight.]],
	level = 13,
	maxhp = 44, maxdam = 36, armor = 24,
	maxexp = 78, maxgold = 26,
	immune = 0,
	maxmp = 43,
	speech = {
		start = { "*rattles loudly*", "*clatters, many bones at once*", chance = 30 },
		turn = { "*clack clack*", chance = 15 },
		winning = { "*rattles*", chance = 25 },
		losing = { "*clatter*", chance = 25 },
		hurt = { "*rattles angrily*", chance = 20 },
		death = { "*comes apart in many pieces*", chance = 60 },
		victory = { "*rattles*", chance = 30 },
	},
}
