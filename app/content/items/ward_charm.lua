-- app/content/items/ward_charm.lua :: Ward Charm, a charm that casts Fend, sold in the markets of Narcissa and Hambry.
return {
	name = "Ward Charm",
	description = "A bronze disc engraved with a ring of runes. Equipped, it casts Fend in a fight " ..
		"without costing MP, four charges at a time. Rest at an inn to recharge it.",
	lore = [[
Mages' guilds sell the disc to any apprentice with the coin, and the guilds insist it is the
same bronze as the bells on the Narcissa walls. It is a useful thing to have in a fight that
has turned against you. The runes have to be cut fresh by someone who knows them, so the
discs cost more than a Mage's first month of rent and are sold in pairs to discourage theft.]],
	category = "accessory",
	price = 1500,
	casts = "fend",
	charges = 4,
}
