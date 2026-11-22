-- app/content/monsters/serafiend.lua :: the Serafiend (the original game's monster 114).
return {
	name = "Serafiend",
	lore = [[
A seraph that fell out of the choir and kept its voice. Serafiends still speak in the
language of the heavens, and their words are sweet at first and sour by the second
sentence. They have been seen guarding the old chapels in the hills above Roma, where the
bells no longer ring and nobody has asked why.]],
	icon = "serafiend",
	level = 38,
	maxhp = 170, maxdam = 155, armor = 125,
	maxexp = 555, maxgold = 185,
	immune = 0,
	maxmp = 137,
	speech = {
		start = { "Rest, child. The light is patient.", "Do not be afraid, {player}.", chance = 45 },
		turn = { "Your fear is a kind of prayer.", "Be still.", chance = 15 },
		winning = { "Heaven forgives you. I do not.", chance = 30 },
		losing = { "I was made to shine, not to fall!", chance = 40 },
		hurt = { "You strike a holy thing.", chance = 22 },
		death = { "The choir... will sing without me...", chance = 65 },
		victory = { "Rest now, child.", chance = 50 },
	},
}
