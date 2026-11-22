-- app/content/items/halo_charm.lua :: Halo Charm, a charm that resists holy, sold in Hambry, Gilead and Endworld.
return {
	name = "Halo Charm",
	description = "A clear stone cut like a crown. Holy Resistance +25%: holy damage is cut by a quarter.",
	lore = [[
A clear stone cut like a crown, set in a band of worn silver. The temples in Hambry and
Gilead sell them to the faithful who are going on to the far towns, and the priests keep
the price high so that the faithful value them. Endworld's guards say a Halo Charm will
not stop a claw, but it does make a man stand up straighter when the claw comes.]],
	icon = "halo_charm",
	category = "accessory",
	price = 2400,
	modifiers = { { kind = "resist", element = "holy", amount = 25 } },
}
