-- app/content/items/wand.lua :: the Wand (new in 2.4), the first item with an effect: a
-- weapon that casts a spell (casts: a spell key) with charges instead of MP. Each wand
-- has its own charges (user_items.charges), full when obtained; using it in a fight (it
-- must be equipped) casts the spell and spends a charge, and resting at an inn refills
-- the charges of equipped items.
return {
	name = "Wand",
	description = "A short rod of polished ash. Equipped, it casts Magic Bolt in a fight without costing MP, " ..
		"one charge at a time. Rest at an inn to recharge it.",
	lore = [[
Midworld's apprentices carve these from fallen ash and fill them with the sparks they
cannot yet hold in their heads. A tired Mage with a good wand is never quite out of tricks.]],
	category = "weapon",
	price = 75,
	attack = 2,
	casts = "magic_bolt",           -- the spell it casts (app/content/spells/magic_bolt.lua)
	charges = 5,                    -- charges when full
	icon = "wand",                  -- public/images/items/wand.png
}
