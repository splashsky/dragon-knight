-- app/content/items/cure_all.lua :: cures every harmful status and restores some HP.
return {
	name = "Cure-All",
	description = "Cures every harmful effect and restores 40 hit points, in a fight or out of it.",
	lore = [[
A dark green syrup from the abbey cellars in Hambry, sold in squat blue bottles with the
abbot's seal on the cork. It was first made for the monks who came back from the marsh
with blood poisoning and worse, and it still tastes of the marsh. A bottle costs more
than most people earn in a week, and the abbey says that is because it works on
everything.]],
	icon = "cure_all",
	category = "consumable",
	price = 350,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 40,                     -- the most HP it restores
	messages = {
		used = "You have used the %s. It cures your ills and gives you %d Hit Points.",
		nothing = "You don't need the %s now. Please go back and try again.",
		nothing_town = "You don't need to use the %s now.",
	},
	can_use = function(u)
		if #u.caster:statuses("harmful") == 0 and u.caster.hp >= u.caster.maxhp then
			return u:refuse(u.in_fight and "nothing" or "nothing_town", u.name)
		end
	end,
	use = function(u)
		u.caster:cure("harmful")
		u:say("used", u.name, u.caster:heal("hp", u.power))
	end,
}
