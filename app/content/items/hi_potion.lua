-- app/content/items/hi_potion.lua :: a stronger healing potion (250 hit points).
return {
	name = "Hi-Potion",
	description = "Restores 250 hit points, in a fight or out of it.",
	lore = [[
A deep amber draught from the big apothecary in Bris, bottled in the thick brown glass
that keeps the light out. The apothecary sells it to caravan guards on contract, a dozen
at a time, and makes them sign for each bottle. It is bitter and warm and works faster
than a potion, which is the point of the price.]],
	category = "consumable",
	price = 180,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 250,                    -- the most HP it restores
	messages = {
		used = "You have used the %s, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use the %s now.",
	},
	can_use = function(u)
		if u.caster.hp >= u.caster.maxhp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
	end,
	use = function(u)
		u:say("used", u.name, u.caster:heal("hp", u.power))
	end,
}
