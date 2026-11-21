-- app/content/items/elixir.lua :: restores both hit points and magic points.
return {
	name = "Elixir",
	description = "Restores 400 hit points and 60 magic points, in a fight or out of it.",
	lore = [[
A gold-flecked liquid sold in heavy stoppered flasks, made in a single workshop in Gilead
by a family who will not let anyone else into the cellar. It is the only remedy the
border towns trust to put a fighter back on both feet and a mage back on both knees. The
family's motto is painted over the door, and the price is painted over the motto.]],
	category = "consumable",
	price = 900,
	max_stack = 5,
	usable_in = "both",
	target = "self",
	power = 400,                    -- the most HP it restores
	data = { mp = 60 },             -- the most MP it restores
	messages = {
		used = "You have used the %s, and gained %d Hit Points and %d Magic Points.",
		full = "Your Hit Points and Magic Points are already full. Please go back and try again.",
		full_town = "Your Hit Points and Magic Points are already full. You don't need to use the %s now.",
	},
	can_use = function(u)
		if u.caster.hp >= u.caster.maxhp and u.caster.mp >= u.caster.maxmp then
			return u:refuse(u.in_fight and "full" or "full_town", u.name)
		end
	end,
	use = function(u)
		local hp = u.caster:heal("hp", u.power)
		local mp = u.caster:heal("mp", u.data.mp)
		u:say("used", u.name, hp, mp)
	end,
}
