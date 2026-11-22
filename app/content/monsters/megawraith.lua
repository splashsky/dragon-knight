-- app/content/monsters/megawraith.lua :: the Megawraith (the original game's monster 61).
return {
	name = "Megawraith",
	lore = [[
A megawraith is a wraith grown fat on the dead of a battlefield, a grey shape taller than
a door. Where lesser wraiths drift, the megawraith drives, pushing its cold into the bones
of anyone who stands near it. The dead of Gilead are said to have stopped reaching the
afterlife because of them. Priests recommend holy water and running, in that order.]],
	icon = "megawraith",
	level = 21,
	maxhp = 70, maxdam = 60, armor = 46,
	maxexp = 155, maxgold = 52,
	resist = { neutral = 35, shadow = 75, frost = 50, poison = 100, holy = -75 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	attack_element = "shadow",
	maxmp = 74,
	speech = {
		start = { "Your bones will do.", chance = 40 },
		turn = { "So many... so cold.", chance = 15 },
		winning = { "Join the rest, {player}.", chance = 30 },
		hurt = { "Shhh! You disturb the dead!", chance = 25 },
		death = { "Back... to the grave...", chance = 55 },
		victory = { "Another for the field.", chance = 40 },
	},
}
