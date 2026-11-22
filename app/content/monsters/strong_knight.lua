-- app/content/monsters/strong_knight.lua :: the Strong Knight (the original game's monster 104).
return {
	name = "Strong Knight",
	lore = [[
A knight of the old garrison of Gilead who was told, once too often, that he was not
strong enough to hold the gate. He still holds it, and he still takes the challenge
personally. Sellers in Gilead's market have learned to sell his kind a shield, not a
sword, since he breaks the swords.]],
	icon = "strong_knight",
	level = 35,
	maxhp = 150, maxdam = 135, armor = 110,
	maxexp = 365, maxgold = 122,
	maxmp = 125,
	speech = {
		start = { "Name yourself, {player}, and stand where I can see you.", chance = 40 },
		turn = { "Hold!", "Is that all you have?", chance = 15 },
		winning = { "The gate stays shut.", chance = 30 },
		losing = { "I have held worse than you!", chance = 35 },
		hurt = { "A glancing blow.", "Harder!", chance = 20 },
		death = { "The gate... is yours.", chance = 65 },
		victory = { "Next challenger.", chance = 50 },
	},
}
