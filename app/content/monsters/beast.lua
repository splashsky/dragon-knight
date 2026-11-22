-- app/content/monsters/beast.lua :: the Beast (the original game's monster 67).
return {
	name = "Beast",
	lore = [[
The Beast is a shapeless hunter of the far hills near Gilead, a hulking mass of fur, claw
and teeth with no clear face. Scholars argue whether it is one creature or a whole kind,
because the hunters who have seen one describe it differently each time. What is agreed
is that it hunts alone, hides well in the snow, and will follow a wounded traveller for
days. Carry more bandages than seems sensible.]],
	icon = "beast",
	level = 23,
	maxhp = 76, maxdam = 66, armor = 52,
	maxexp = 170, maxgold = 57,
	maxmp = 82,
	speech = {
		start = { "*snorts*", chance = 30 },
		turn = { "Hhhrr.", chance = 10 },
		winning = { "*pads closer*", chance = 25 },
		hurt = { "GRRAH!", chance = 30 },
		death = { "*collapses into the snow*", chance = 50 },
		victory = { "*drags the carcass off*", chance = 30 },
	},
}
