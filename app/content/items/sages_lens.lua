-- app/content/items/sages_lens.lua :: Sage's Lens, a monster drop with a cost.
return {
	name = "Sage's Lens",
	description = "A lens of pale crystal set in a frame of bone. Adds experience gained from each " ..
		"fight, but reduces maximum hit points.",
	lore = [[
A monk in the hills above Hambry grinds these lenses for scholars who want to read by candle
until midnight, and he sells them at cost because he says a clear eye is worth more than a
clever one. Monsters drop them now and then, cracked along the same line. Anyone who wears one
learns faster and bleeds about as fast, which is a trade the monk says every scholar should
make consciously.]],
	icon = "sages_lens",
	category = "accessory",
	drop_level = 30,
	modifiers = {
		{ kind = "stat", stat = "exp_bonus_pct", amount = 25 },
		{ kind = "stat", stat = "maxhp", amount = -20 },
	},
}
