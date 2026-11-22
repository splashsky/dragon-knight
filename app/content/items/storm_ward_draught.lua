-- app/content/items/storm_ward_draught.lua :: a draught that halves the lightning damage
-- you take for a while (the storm_ward status, as the Storm Ward spell). Fights only.
return {
	name = "Storm Ward Draught",
	description = "Halves the lightning damage you take for 80 seconds.",
	icon = "storm_ward_draught",
	category = "consumable",
	price = 240,
	max_stack = 10,
	usable_in = "fight",
	power = 8,                      -- how many ticks the ward lasts
	messages = {
		used = "You have drunk the %s. Lightning will hurt you half as much for %d seconds.",
		failed = "You have drunk the %s, but it fails to take hold.",
	},
	uses = { statuses = { "storm_ward" } },
	use = function(u)
		if not u.caster:afflict("storm_ward", { ticks = u.power }) then return u:say("failed", u.name) end
		u:say("used", u.name, u:seconds(u.power))
	end,
}
