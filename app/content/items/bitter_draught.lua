-- app/content/items/bitter_draught.lua :: heals over time: the regen status for a while, on
-- the map or in a fight.
return {
	name = "Bitter Draught",
	description = "Recovers hit points every 10 seconds for a while, on the map or in a fight.",
	lore = [[
A brown tincture of wormwood and something the healers will not name, poured out of a
wide clay jug in Narcissa's old infirmary. It is so bitter that most people only drink it
once, and then they carry it for the rest of their lives. The healers say it closes wounds
slowly and steadily, which is better than closing them quickly and opening them again on
the next hill.]],
	icon = "bitter_draught",
	category = "consumable",
	price = 160,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 10,                     -- ticks of regeneration
	data = { amount = 12 },          -- hit points it recovers each tick
	uses = { statuses = { "regen" } },
	messages = {
		used = "You have drunk the %s, and will regenerate %d Hit Points for %d seconds.",
		used_town = "You have drunk the %s, and will regenerate %d Hit Points for %d seconds.",
	},
	use = function(u)
		u.caster:afflict("regen", { ticks = u.power, amount = u.data.amount })
		u:say(u.in_fight and "used" or "used_town", u.name, u.data.amount, u:seconds(u.power))
	end,
}
