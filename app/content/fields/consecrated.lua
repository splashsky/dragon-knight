-- app/content/fields/consecrated.lua :: consecrated ground (an aura: only from a spell, a
-- Paladin's Consecrate): holy light strong, shadow weak.
return {
	name = "Consecrated Ground",
	description = "Hallowed ground: holy light is stronger and shadow weaker.",
	lore = [[
A Paladin's Consecrate lays a soft light over the ground, and it drives out any other
aura already there. The Order keeps a page for every field it has held in the oath book
at the Midworld chapel. Shadow creatures do not like to stand in the light, and the ones
that do are easy to spot by the way they squint.]],
	icon = "consecrated",
	group = "aura",
	damage = { holy = 25, shadow = -25 },
	messages = {
		begins = "A soft light settles over the field: the ground is consecrated.",
		ends = "The holy light fades from the ground.",
	},
}
