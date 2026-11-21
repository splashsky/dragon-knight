-- app/content/items/tinker_buckle.lua :: Tinker's Buckle, a monster drop.
return {
	name = "Tinker's Buckle",
	lore = [[
A brass buckle that a tinker in Roma stopped making after the third time his customers came
back with it bent. The ones left over are pitted and tough, and the goblins that dropped
them had clearly been using them as belt plates. Soldiers sew them onto the front of a
jerkin, where a blade is most likely to glance off.]],
	category = "accessory",
	drop_level = 7,
	modifiers = { { kind = "stat", stat = "defense", amount = 10 } },
}
