-- app/content/items/war_standard.lua :: a knight's standard: the monsters' way to raise a war
-- banner (the object war_banner: app/content/interactables/war_banner.lua) over their own side.
-- Monsters only, sold nowhere; refused when three objects already stand.
return {
	name = "War Standard",
	description = "Raises a war banner over the user's side of the field: everyone there deals 25% more damage while it stands.",
	icon = "war_standard",
	category = "consumable",
	max_stack = 1,
	usable_in = "fight",
	target = "self",
	messages = {
		used = "You raise the %s.",
		no_room = "There is no room for another object on the field.",
		enemy = {
			used = "The monster raises a war standard.",
		},
	},
	uses = { interactables = { "war_banner" } },
	can_use = function(u)
		if u.place_room < 1 then return u:refuse("no_room") end
	end,
	use = function(u)
		u:place("war_banner")
		u:say("used", u.name)
	end,
}
