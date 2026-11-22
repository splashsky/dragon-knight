-- app/content/items/halo_charm.lua :: Halo Charm, a charm that resists holy, sold in Hambry, Gilead and Endworld.
return {
	name = "Halo Charm",
	description = "A clear stone cut like a crown. Holy Resistance +25%: holy damage is cut by a quarter.",
	icon = "halo_charm",
	category = "accessory",
	price = 2400,
	modifiers = { { kind = "resist", element = "holy", amount = 25 } },
}
