-- app/content/items/frost_ward_draught.lua :: a draught that halves the frost damage you
-- take for a while (the frost_ward status, as the Frost Ward spell). Fights only.
return {
	name = "Frost Ward Draught",
	description = "Halves the frost damage you take for 80 seconds.",
	icon = "frost_ward_draught",
	category = "consumable",
	price = 240,
	max_stack = 10,
	usable_in = "fight",
	power = 8,                      -- how many ticks the ward lasts
	messages = {
		used = "You have drunk the %s. Frost will hurt you half as much for %d seconds.",
		failed = "You have drunk the %s, but it fails to take hold.",
	},
	uses = { statuses = { "frost_ward" } },
	use = function(u)
		if not u.caster:afflict("frost_ward", { ticks = u.power }) then return u:say("failed", u.name) end
		u:say("used", u.name, u:seconds(u.power))
	end,
}
