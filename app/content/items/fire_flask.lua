-- app/content/items/fire_flask.lua :: a thrown flask of lamp oil that sets the monster
-- alight (the burning status: fire). Fights only; monsters immune to fire or warding off
-- burning for certain are refused it (it isn't used up).
return {
	name = "Fire Flask",
	description = "Throws burning oil that sets the monster alight for a while. Some monsters are immune.",
	lore = [[
Lamp oil in a clay flask with a rag stuffed in the neck, sold by the lamplighters' guild
at a price that is never quite explained. The thrower lights the rag and throws it. The
flask breaks on the monster and the oil keeps burning on its hide until it is spent. A
guild man in Roma says the trick is to throw it before the thing is close enough to step
on your feet.]],
	icon = "fire_flask",
	category = "consumable",
	price = 50,
	max_stack = 10,
	usable_in = "fight",
	power = 4,                      -- how many ticks it burns
	data = { amount = 7 },          -- hit points it burns away each tick
	messages = {
		used = "You throw the %s. The monster catches fire and burns for %d seconds.",
		immune = "You throw the %s, but the monster is immune to it.",
		resisted = "You throw the %s, but the monster resists it.",
	},
	uses = { statuses = { "burning" } },
	can_use = function(u)
		if u.target:immune_to("fire") or u.target:ward("burning") == 100 then return u:refuse("immune", u.name) end
	end,
	use = function(u)
		if not u.target:afflict("burning", { ticks = u.power, amount = u.data.amount }) then
			return u:say("resisted", u.name)
		end
		u:say("used", u.name, u:seconds(u.power))
	end,
}
