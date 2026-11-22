-- app/content/items/storm_lance.lua :: the Storm Lance (a lance that casts Lightning Lance).
return {
	name = "Storm Lance",
	description = "A long lance of blued steel with a copper wire down its shaft. Equipped, it casts Lightning Lance in a fight without costing MP, one charge at a time. You must recharge on the next turn unless the blast slays the monster. Rest at an inn to recharge it.",
	lore = [[
Endworld's storm-watchers string a copper wire down the shaft of each lance and hang it
from a tower in the spring. Three or four good storms and the wire holds enough charge
to be worth carrying. Mages who buy one are warned that the lance is heavy, the spell
costs the Mage a turn of standing still, and the wire does not forgive a wet hand.]],
	icon = "storm_lance",
	category = "weapon",
	price = 35000,
	attack = 150,
	element = "lightning",
	casts = "lightning_lance",      -- the spell it casts (app/content/spells/lightning_lance.lua)
	charges = 4,                    -- charges when full
}
