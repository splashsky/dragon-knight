-- app/content/items/trail_snack.lua :: a cheap snack that restores a little HP and TP.
return {
	name = "Trail Snack",
	description = "Restores 15 hit points and 10 travel points, in a fight or out of it.",
	lore = [[
A square of oats, dried fruit and something sweet enough to hide the grit. Bakers in the
market streets pack them in wax paper, and farmers' children eat them on the walk out to
the fields. It does not fill you up, but it puts the legs back under you for a while.]],
	category = "consumable",
	price = 20,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 15,                     -- the most HP it restores
	data = { tp = 10 },             -- the most TP it restores
	messages = {
		used = "You have eaten the %s, and gained %d Hit Points and %d Travel Points.",
		full = "You are already full of hit points and travel points. Please go back and try again.",
		full_town = "You are already full of hit points and travel points. You don't need to eat the %s now.",
	},
	can_use = function(u)
		if u.caster.hp >= u.caster.maxhp and u.caster.tp >= u.caster.maxtp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
	end,
	use = function(u)
		local hp = u.caster:heal("hp", u.power)
		local tp = u.caster:heal("tp", u.data.tp)
		u:say("used", u.name, hp, tp)
	end,
}
