-- app/content/monsters/hellhound.lua :: the Hellhound (the original game's monster 57).
return {
	name = "Hellhound",
	lore = [[
Hellhounds run in pairs, and sometimes in larger packs, along the hot road between Bris
and Kalle. Their breath smells of sulphur and can be smelt a mile off, which is the only
warning most travellers get. A hellhound is faster than any horse on that road, so the
common advice is to fight from a doorway rather than run. Some of the old soldiers in
Kalle keep a hellhound's tooth as a charm.]],
	icon = "hellhound",
	level = 20,
	maxhp = 66, maxdam = 56, armor = 44,
	maxexp = 140, maxgold = 47,
	immune = 0,
	maxmp = 70,
	speech = {
		start = { "*snarls*", "Hot meat... good.", chance = 35 },
		turn = { "Grrrrah!", chance = 15 },
		winning = { "Bones next.", chance = 25 },
		hurt = { "Yaaarp!", chance = 30 },
		death = { "*whimpers*", chance = 50 },
		victory = { "*gnaws*", chance = 35 },
	},
}
