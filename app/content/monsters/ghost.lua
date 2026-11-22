-- app/content/monsters/ghost.lua :: the Ghost (the original game's monster 17).
return {
	name = "Ghost",
	lore = [[
The spirit of someone who died on the road between Midworld and Kalle and never quite
left. It drifts through old graveyards and ruined inns, moaning about a debt nobody
remembers. Priests in Midworld will bless a grave for a few gold, which keeps most ghosts
quiet and some of them away.]],
	icon = "ghost",
	level = 6,
	maxhp = 24, maxdam = 20, armor = 8,
	maxexp = 28, maxgold = 9,
	resist = { shadow = 75, poison = 100, neutral = 25, holy = -50 },
	ward = { sleep = 100, poison = 100 },       -- Sleep Powder and poison fail here
	attack_element = "shadow",
	maxmp = 22,
	speech = {
		start = { "Wh... who are you?", chance = 30 },
		turn = { "I owe a debt. Who did I owe?", "Cold... so cold...", chance = 20 },
		hurt = { "Oh! Oh, that hurts.", chance = 25 },
		losing = { "Let me rest. Please let me rest.", chance = 25 },
		death = { "Finally... the debt is paid.", chance = 40 },
		victory = { "Another one for the grave, {player}.", chance = 25 },
	},
}
