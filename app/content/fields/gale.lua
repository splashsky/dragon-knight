-- app/content/fields/gale.lua :: a gale (a Gale spell's; the weather never brings it, and it
-- takes the sky's place while it lasts): wind strong, fire a little stronger, frost weaker,
-- everyone unsteady, and a wind so high that it fans a fire (a barrel's lighting chance) without
-- putting it out, unlike the storms'.
return {
	name = "Gale",
	description = "A howling wind: wind damage is stronger, fire a little stronger and frost weaker, everyone is unsteady, and it fans a fire without putting it out.",
	lore = [[
Storms bring their own wind, and where the rain falls a fire does not last. The Gale is the
one a Mage calls up on a clear day: it takes the sky's place, brings no rain, and fans a fire
without putting it out. Mages of Hambry say it is the only part of the weather a man can
hire. The watchmen on the Gilead road tell travellers to stand clear of the old dead trees
while it blows.]],
	icon = "gale",
	group = "sky",
	wind = 3,   -- a gale (from 0, calm, to 3)
	damage = { wind = 30, fire = 10, frost = -10 },
	stats = { dexterity = -10 },
	messages = {
		begins = "A gale tears across the field.",
		ends = "The gale dies down.",
	},
}
