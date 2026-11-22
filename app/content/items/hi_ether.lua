-- app/content/items/hi_ether.lua :: a stronger magic restore (100 magic points).
return {
	name = "Hi-Ether",
	description = "Restores 100 magic points, in a fight or out of it.",
	lore = [[
A cold blue distillate that the mages of Narcissa make in copper stills on the north wall
of the college, because the smell of it set off too many fires in the old lodgings. Each
flask is labelled with the name of the mage who made it, and the college will refuse a
sale to anyone it does not know. Court mages buy it by the crate and use it in the
second hour of a long fight.]],
	icon = "hi_ether",
	category = "consumable",
	price = 300,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 100,                    -- the most MP it restores
	messages = {
		used = "You have used the %s, and gained %d Magic Points.",
		full = "Your Magic Points are already full. Please go back and try again.",
		full_town = "Your Magic Points are already full. You don't need to use the %s now.",
	},
	can_use = function(u)
		if u.caster.mp >= u.caster.maxmp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
	end,
	use = function(u)
		u:say("used", u.name, u.caster:heal("mp", u.power))
	end,
}
