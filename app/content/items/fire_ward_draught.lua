-- app/content/items/fire_ward_draught.lua :: a draught that halves the fire damage you take
-- for a while (the fire_ward status, as the Fire Ward spell). Fights only.
return {
	name = "Fire Ward Draught",
	description = "Halves the fire damage you take for 80 seconds.",
	lore = [[
A pale yellow draught in a stoppered vial, sold in almost every town on the road. Mages
say it is the Fire Ward spell in a bottle, for those who have not yet got round to
learning the spell. The apothecaries make it in batches of a few dozen and sell out before
the week is done. Nobody has yet asked them what goes into it, and they prefer it that
way.]],
	icon = "fire_ward_draught",
	category = "consumable",
	price = 240,
	max_stack = 10,
	usable_in = "fight",
	power = 8,                      -- how many ticks the ward lasts
	messages = {
		used = "You have drunk the %s. Fire will hurt you half as much for %d seconds.",
		failed = "You have drunk the %s, but it fails to take hold.",
	},
	uses = { statuses = { "fire_ward" } },
	use = function(u)
		if not u.caster:afflict("fire_ward", { ticks = u.power }) then return u:say("failed", u.name) end
		u:say("used", u.name, u:seconds(u.power))
	end,
}
