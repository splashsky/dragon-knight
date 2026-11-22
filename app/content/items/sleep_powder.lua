-- app/content/items/sleep_powder.lua :: puts a monster to sleep (a thrown pinch; immune 2
-- stops it). Fights only.
return {
	name = "Sleep Powder",
	description = "Throws a grey dust that puts the monster to sleep. Some monsters are immune.",
	lore = [[
A grey dust ground from poppy heads and a root the herbwives keep in tins with the
labels scraped off. A pinch thrown into a monster's face is enough for most beasts to
sit down and start snoring. Guards in Roma say the trick is to be upwind, and they say
it with the air of men who have learned it the hard way.]],
	icon = "sleep_powder",
	category = "consumable",
	price = 45,
	max_stack = 10,
	usable_in = "fight",
	power = 5,                      -- the chance (of 15) that it stays asleep each turn
	messages = {
		used = "You throw the %s. The monster falls asleep.",
		immune = "You throw the %s, but the monster is immune to it.",
	},
	uses = { statuses = { "sleep" } },
	can_use = function(u)
		if u.target.immune == 2 then return u:refuse("immune", u.name) end
	end,
	use = function(u)
		u.target:sleep(u.power)
		u:say("used", u.name)
	end,
}
