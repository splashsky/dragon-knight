-- app/content/monsters/dawkin.lua :: the Dawkin (the original game's monster 62).
return {
	name = "Dawkin",
	lore = [[
The Dawkin is what a Dawk becomes after surviving long enough to learn a few words. They
lead the gangs in the mines beyond Hambry and keep the best loot for themselves, which
mostly means the miners' gold. A Dawkin is cunning enough to retreat when badly hurt and
come back with friends. One that talks has usually already decided what it will do with
you.]],
	icon = "dawkin",
	level = 21,
	maxhp = 70, maxdam = 60, armor = 46,
	maxexp = 155, maxgold = 52,
	immune = 0,
	maxmp = 74,
	speech = {
		start = { "You lost, {player}. Dawkin know the way out.", chance = 40 },
		turn = { "Dawk not stupid.", chance = 15 },
		winning = { "Gold for Dawkin.", "Put down the sword, {player}.", chance = 30 },
		hurt = { "Dawkin bleed? Impossible.", chance = 25 },
		losing = { "Retreat! Get the others!", chance = 35 },
		death = { "Tell the rest... Dawk... lost.", chance = 50 },
		victory = { "Dawkin takes the gold.", chance = 60 },
	},
}
