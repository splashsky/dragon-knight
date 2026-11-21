-- app/content/items/bitter_draught.lua :: heals over time: the regen status, for the next
-- moves on the map or the next turns of a fight.
return {
	name = "Bitter Draught",
	description = "Recovers hit points with every move on the map (or every turn of a fight) for a while.",
	lore = [[
A brown tincture of wormwood and something the healers will not name, poured out of a
wide clay jug in Narcissa's old infirmary. It is so bitter that most people only drink it
once, and then they carry it for the rest of their lives. The healers say it closes wounds
slowly and steadily, which is better than closing them quickly and opening them again on
the next hill.]],
	category = "consumable",
	price = 160,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 10,                     -- moves (turns in a fight)
	data = { amount = 12 },          -- hit points it recovers each move or turn
	uses = { statuses = { "regen" } },
	messages = {
		used = "You have drunk the %s, and will regenerate %d Hit Points for %d turns.",
		used_town = "You have drunk the %s, and will regenerate %d Hit Points for the next %d moves.",
	},
	use = function(u)
		u.caster:afflict("regen", { turns = u.power, amount = u.data.amount })
		u:say(u.in_fight and "used" or "used_town", u.name, u.data.amount, u.power)
	end,
}
