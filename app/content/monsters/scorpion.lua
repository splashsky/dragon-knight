-- app/content/monsters/scorpion.lua :: the Scorpion (the original game's monster 12).
local function unpoisoned(m)
	return not m.target:has_status("poison")
end

return {
	name = "Scorpion",
	lore = [[
A desert-bred scorpion, big as a dog and the colour of old tea, that hides under rocks along
the road south of Roma. Its tail is the danger, and its sting leaves a hot ache that lasts
a day. Caravan drivers shake out their boots every morning and do not trust a dark corner.]],
	icon = "scorpion",
	level = 5,
	maxhp = 18, maxdam = 14, armor = 6,
	maxexp = 20, maxgold = 7,
	resist = { poison = 50, fire = -25 },
	ward = { poison = 100 },
	attack_element = "poison",
	maxmp = 17,
	spells = {
		-- poisons you unless you are already poisoned
		{ spell = "poison", weight = 1, when = unpoisoned },
	},
	speech = {
		start = { "*clicks its claws*", chance = 20 },
		turn = { "*tail twitches*", chance = 10 },
		hurt = { "*hisses*", chance = 20 },
		losing = { "*scuttles under a rock*", chance = 15 },
		death = { "*curls up*", chance = 30 },
		victory = { "*clicks happily*", chance = 15 },
	},
}
