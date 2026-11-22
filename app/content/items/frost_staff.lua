-- app/content/items/frost_staff.lua :: the Frost Staff (a staff that casts Frostbite).
return {
	name = "Frost Staff",
	description = "A pale ash staff with a rime of silver at its head. Equipped, it casts Frostbite in a fight without costing MP, one charge at a time. Rest at an inn to recharge it.",
	lore = [[
The Kalle miners who go down after bears carry these staves, because a cave bear that
has been frosted sits down. The silver rime on the head is put on by a cold-smith who
works the mine's winter ice pits. A Mage who buys one is usually going to the back
passages next, and the staff does not care whether anyone thinks that is wise.]],
	icon = "frost_staff",
	category = "weapon",
	price = 700,
	attack = 6,
	casts = "frostbite",            -- the spell it casts (app/content/spells/frostbite.lua)
	charges = 5,                    -- charges when full
}
