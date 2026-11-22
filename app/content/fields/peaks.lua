-- app/content/fields/peaks.lua :: the mountains (the land's, lib/terrain.lua): thin air and
-- exposed ledges, frost, wind and lightning stronger.
return {
	name = "High Peaks",
	description = "Bare rock and thin air: frost, wind and lightning are stronger, fire is weaker and burns out sooner, and everyone is short of breath.",
	lore = [[
Bare rock and ledges, with a drop on one side and the wind on the other. Frost, wind and
lightning hit harder up here, fire is weaker and burns out sooner, and the thin air leaves
everyone short of breath. The herders of the passes beyond Kalle climb with a rope, and
they say a fight on a ledge goes to whoever keeps his feet. The dragons of the Kalle peaks
breathe frost, and they know the ledges better than any man.]],
	icon = "peaks",
	group = "terrain",
	damage = { frost = 20, wind = 20, lightning = 15, fire = -10 },
	statuses = { burning = { ticks = -1 } },
	stats = { dexterity = -15, strength = -10 },
}
