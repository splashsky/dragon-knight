-- app/content/items/blessed_mace.lua :: the Blessed Mace (a mace whose blows are holy).
return {
	name = "Blessed Mace",
	description = "Attack 70. Its blows deal Holy damage: good against the dead and the damned, wasted on the holy.",
	lore = [[
A heavy flanged mace, blessed in the Hambry temple by a priest who has blessed more of
them than he can count. Pilgrims going north buy them for the road, and Gilead's shrine
keeps a rack by the door. The priests say a mace is only as holy as the hand that swings
it. Most of the pilgrims who buy one are not sure whose hand that is.]],
	icon = "blessed_mace",
	category = "weapon",
	price = 2400,
	attack = 70,
	element = "holy",
}
