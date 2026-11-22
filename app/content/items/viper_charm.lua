-- app/content/items/viper_charm.lua :: Viper Charm, a charm that wards off poison and venom, sold in Kalle, Narcissa and Hambry.
return {
	name = "Viper Charm",
	description = "A green stone from a snake-charmer's belt. Poison Ward +50% and Venom Ward +50%: half of the attempts to poison you fail.",
	icon = "viper_charm",
	category = "accessory",
	price = 1800,
	modifiers = {
		{ kind = "ward", status = "poison", amount = 50 },
		{ kind = "ward", status = "venom", amount = 50 },
	},
}
