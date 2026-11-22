-- app/content/items/viper_charm.lua :: Viper Charm, a charm that wards off poison and venom, sold in Kalle, Narcissa and Hambry.
return {
	name = "Viper Charm",
	description = "A green stone from a snake-charmer's belt. Poison Ward +50% and Venom Ward +50%: half of the attempts to poison you fail.",
	lore = [[
A green stone taken from a snake-charmer's belt, which the charmer swears was a gift from
a grateful adder. Kalle's charmers sell them to travellers bound for the bogs, and
Kalle's apothecaries will not sell one without a tin of Antidote to go with it. The
stones are worn smooth from handling, and the sellers say every one of them came from the
same belt.]],
	icon = "viper_charm",
	category = "accessory",
	price = 1800,
	modifiers = {
		{ kind = "ward", status = "poison", amount = 50 },
		{ kind = "ward", status = "venom", amount = 50 },
	},
}
