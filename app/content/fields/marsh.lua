-- app/content/fields/marsh.lua :: the Thornbog's ground (the land's, lib/terrain.lua): rot and
-- bites, poisons stronger, fire damp, and slogging feet.
return {
	name = "Marsh",
	description = "Sucking bog and stagnant water: poison and earth are stronger, poisons bite deeper, fire burns out sooner, and everyone slogs.",
	icon = "",
	group = "terrain",
	damage = { poison = 15, earth = 10, fire = -10 },
	statuses = {
		poison = { scale = { min = 125, max = 125 } },
		venom = { scale = { min = 125, max = 125 } },
		burning = { ticks = -1 },
	},
	stats = { dexterity = -15 },
}
