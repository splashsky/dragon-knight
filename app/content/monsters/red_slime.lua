-- app/content/monsters/red_slime.lua :: the Red Slime (the original game's monster 2).
return {
	name = "Red Slime",
	lore = [[
A redder and crosser cousin of the blue slime, found in the damp cellars and ditches around
Midworld. It stings a little more than its blue relative, and it does not take kindly to
being poked. Cellar keepers swear a pinch of salt sends one back down the drain, though it
never works twice.]],
	icon = "red_slime",
	level = 1,
	maxhp = 6, maxdam = 5, armor = 1,
	maxexp = 2, maxgold = 1,
	immune = 0,
	maxmp = 5,
	speech = {
		start = { "*hisses wetly*", chance = 20 },
		turn = { "*bubbles angrily*", chance = 10 },
		hurt = { "*bloop! bloop!*", chance = 20 },
		death = { "*sizzles out*", chance = 30 },
		victory = { "*bubbles smugly*", chance = 15 },
	},
}
