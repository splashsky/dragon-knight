-- app/content/monsters/drakelor.lua :: the Drakelor (the original game's monster 8).
return {
	name = "Drakelor",
	lore = [[
A drake that has grown older and sly, and now hunts the road between Roma and Bris. Its
scales are a dull grey-green that blends into the rocks, so travellers usually see it only
when it bites. Bris guards pay a bounty for its claws, which are sharp enough to serve as
a needle.]],
	icon = "drakelor",
	level = 3,
	maxhp = 14, maxdam = 12, armor = 4,
	maxexp = 10, maxgold = 3,
	resist = { frost = -25 },
	ward = { poison = 25 },                     -- poison sometimes doesn't take hold
	maxmp = 9,
	speech = {
		start = { "Another one for the road, is it?", chance = 30 },
		turn = { "Hold still. This will only sting.", "Sly little thing, aren't you?", chance = 15 },
		hurt = { "Careful with those claws!", chance = 25 },
		losing = { "You will not get a bounty for killing me, you know.", chance = 25 },
		death = { "Tell the guards I was... no. Don't.", chance = 30 },
		victory = { "Dinner was worth the wait.", chance = 20 },
	},
}
