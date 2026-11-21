-- app/content/monsters/figment.lua :: the Figment (the original game's monster 56).
return {
	name = "Figment",
	lore = [[
A figment is a thing made from a dream someone had too often, given a body that is never
quite solid. It turns up in the shuttered houses of Kalle at night, wearing the shape of a
friend or a lost parent, and waits for a hero to come closer. Hurt spells pass straight
through it, so warriors and their blades must do the work. Dreamers in Narcissa say a
figment fades if you stop believing in it, which is easier said than done.]],
	level = 19,
	maxhp = 64, maxdam = 55, armor = 42,
	maxexp = 140, maxgold = 47,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 64,
	speech = {
		start = { "Come closer. I have been waiting.", chance = 35 },
		turn = { "You remember me, don't you?", chance = 15 },
		winning = { "Stay, {player}. Stay with me.", chance = 30 },
		hurt = { "That is not how this goes...", chance = 25 },
		death = { "Wake up... wake up...", chance = 55 },
		victory = { "And now you dream of me.", chance = 40 },
	},
}
