-- app/content/items/lifeward_shield.lua :: the Lifeward Shield (a shield that adds to maximum HP).
return {
	name = "Lifeward Shield",
	lore = [[
A round shield of tough limewood with a rim of red copper, and a small brass plate on the
face where the healers' sign is stamped. Surgeons in Hambry say a wounded man who keeps
his shield up bleeds slower, and they have the stitched arms to show for it. The shield
itself is no heavier than a buckler and sells for a good deal more.]],
	category = "shield",
	price = 4500,
	defense = 45,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 30 } },
}
