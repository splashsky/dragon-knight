-- app/content/items/ether.lua :: restores magic points (new in 2.1).
return {
	name = "Ether",
	description = "Restores 30 magic points, in a fight or out of it.",
	category = "consumable",
	price = 80,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 30,                     -- the most MP it restores
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
