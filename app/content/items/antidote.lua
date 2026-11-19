-- app/content/items/antidote.lua :: cures the harmful statuses (poison, sleep, ...; new in
-- 2.2). Refused when there is nothing to cure.
return {
	name = "Antidote",
	description = "Cures poison and other harmful effects, in a fight or out of it.",
	category = "consumable",
	price = 30,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	messages = {
		used = "You have used the %s, and feel better.",
		nothing = "You don't need the %s now. Please go back and try again.",
		nothing_town = "You don't need to use the %s now.",
	},
	can_use = function(u)
		if #u.caster:statuses("harmful") == 0 then return u:refuse(u.in_fight and "nothing" or "nothing_town", u.name) end
	end,
	use = function(u)
		u.caster:cure("harmful")
		u:say("used", u.name)
	end,
}
