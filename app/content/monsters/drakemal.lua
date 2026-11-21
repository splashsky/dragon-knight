-- app/content/monsters/drakemal.lua :: the Drakemal (the original game's monster 15).
return {
	name = "Drakemal",
	lore = [[
A drake grown big and heavy, with a rough black hide and a temper to match. It guards the
caves in the hills near Bris and will follow a hero for a mile to make sure they do not come
back. Its fire is smoky and short, but close enough to singe a cloak, so keep your distance.]],
	level = 6,
	maxhp = 22, maxdam = 18, armor = 7,
	maxexp = 24, maxgold = 8,
	immune = 0,
	maxmp = 22,
	speech = {
		start = { "Turn back, little {player}. This cave is mine.", chance = 30 },
		turn = { "*smoke curls from its nostrils*", "Grrmph.", chance = 15 },
		hurt = { "Pah! A scratch!", "That one stung.", chance = 25 },
		losing = { "Hah! I will sleep on this, then eat you.", chance = 25 },
		death = { "*the great head drops*", chance = 35 },
		victory = { "Bones for the cave.", chance = 25 },
	},
}
