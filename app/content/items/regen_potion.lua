-- app/content/items/regen_potion.lua :: regeneration for the next moves on the map (a
-- world status: app/content/statuses/regen.lua), or the next turns in a fight (new in
-- 2.2).
local function use(u)
	u.caster:afflict("regen", { turns = u.power, amount = u.data.amount })
	u:say(u.in_fight and "used" or "used_town", u.name, u.data.amount, u.power)
end

return {
	name = "Regen Potion",
	description = "Recovers hit points with every move on the map (or every turn of a fight) for a while.",
	lore = [[
A green syrup that keeps working long after it is swallowed, so wounds knit a little with
every step. Mages in the border towns sell it to travellers who expect to be hurt and have
a long way to go. Taken early, it saves the healer a lot of work.]],
	category = "consumable",
	price = 100,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 10,                     -- moves (turns in a fight)
	data = { amount = 5 },
	uses = { statuses = { "regen" } },
	messages = {
		used = "You have used the %s, and will regenerate %d Hit Points for %d turns.",
		used_town = "You have used the %s, and will regenerate %d Hit Points for the next %d moves.",
	},
	use = use,
}
