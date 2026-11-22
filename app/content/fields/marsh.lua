-- app/content/fields/marsh.lua :: the Thornbog's ground (the land's, lib/terrain.lua): rot and
-- bites, poisons stronger, fire damp, and slogging feet.
return {
	name = "Marsh",
	description = "Sucking bog and stagnant water: poison and earth are stronger, poisons bite deeper, fire burns out sooner, and everyone slogs.",
	lore = [[
Black water, reeds and soft peat, and the bog pulls at every boot. Poison and earth hit
harder in it, poisons bite deeper, and fire is weaker and burns out sooner, so a torch
is no friend in the reeds. The people who live on the Thornbog say the bog takes what it
likes, and it likes whatever is slow. Stilt-hut folk test each step with a long pole
before they put a foot down.]],
	icon = "marsh",
	group = "terrain",
	damage = { poison = 15, earth = 10, fire = -10 },
	statuses = {
		poison = { scale = { min = 125, max = 125 } },
		venom = { scale = { min = 125, max = 125 } },
		burning = { ticks = -1 },
	},
	stats = { dexterity = -15 },
}
