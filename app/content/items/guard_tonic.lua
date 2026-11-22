-- app/content/items/guard_tonic.lua :: a tonic that cuts the damage you take until the end of
-- the fight (the Defense Up status). Fights only.
return {
	name = "Guard Tonic",
	description = "Takes 25% less damage until the end of the fight.",
	lore = [[
A grey, oily tonic that smells of tallow and boiled bark. The guards at the Narcissa gates
drink it before a night watch, and the old ones say it thickens the skin enough to notice
in a fight. The apothecary who sells it insists it is harmless, and the guards insist
nobody has ever asked them to prove it.]],
	icon = "guard_tonic",
	category = "consumable",
	price = 240,
	max_stack = 10,
	usable_in = "fight",
	power = 25,                     -- the percent less damage taken
	messages = {
		used = "You have drunk the %s. You will take %d%% less damage until the fight is over.",
	},
	uses = { statuses = { "uber_defense" } },
	use = function(u)
		u.caster:buff("defense", u.power)
		u:say("used", u.name, u.power)
	end,
}
