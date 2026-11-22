-- app/content/monsters/werewolf.lua :: the Werewolf (the original game's monster 51).
return {
	name = "Werewolf",
	lore = [[
A man who was bitten and has not yet stopped being a man entirely. Werewolves wait at the
edge of villages on the nights of the full moon, and the farmers around Kalle bar their
doors and keep the dogs in. They still understand speech and enjoy using it to mock the
hunters who come looking. Silver is the only thing that reliably ends one, which is why
the smiths charge double for it.]],
	icon = "werewolf",
	level = 17,
	maxhp = 56, maxdam = 48, armor = 38,
	maxexp = 124, maxgold = 41,
	immune = 0,
	maxmp = 57,
	speech = {
		start = { "Run, little hunter. Run.", chance = 40 },
		turn = { "*howls*", "Your fear is sweet, {player}.", chance = 15 },
		winning = { "Do you smell that, {player}? That is your fear.", chance = 30 },
		hurt = { "Argh! That stung.", chance = 30 },
		death = { "The moon... takes me back...", chance = 60 },
		victory = { "Good hunting tonight.", chance = 50 },
	},
}
