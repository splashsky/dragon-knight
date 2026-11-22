-- app/content/items/strength_tonic.lua :: a tonic that adds damage for the rest of the
-- fight (the Damage Up status). Fights only.
return {
	name = "Strength Tonic",
	description = "Deals 25% more damage until the end of the fight.",
	lore = [[
A brown, sharp-tasting tonic of ginger and black pepper, drunk from a thimble-sized cup
before a bout. Gladiators in Kalle drink it at the start of the pit fights, and the pit
master sells it at cost because he says a dull fight pays him less. It does nothing for
the next morning, and the drinkers are not expected to ask.]],
	icon = "strength_tonic",
	category = "consumable",
	price = 240,
	max_stack = 10,
	usable_in = "fight",
	power = 25,                     -- the percent more damage dealt
	messages = {
		used = "You have drunk the %s. You will deal %d%% more damage until the fight is over.",
	},
	uses = { statuses = { "uber_damage" } },
	use = function(u)
		u.caster:buff("damage", u.power)
		u:say("used", u.name, u.power)
	end,
}
