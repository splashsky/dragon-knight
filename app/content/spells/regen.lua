-- app/content/spells/regen.lua :: the caster regenerates hit points every 10 seconds, in a
-- fight or on the map (the status regen is a world status too).
-- Learned by no class by default.
return {
	name = "Regen",
	description = "Recovers hit points every 10 seconds, in a fight or out of it.",
	lore = [[
Regen is a slow mending that Mages in Narcissa picked up from watching the town's cats, which
heal scratches overnight. It closes small wounds a little each turn, in a fight or on the road.
It helps on long walks and long fights, but it will not close a deep cut.]],
	icon = "regen",
	mp = 8,
	power = 5,                  -- ticks of regeneration, in a fight or out of it
	usable_in = "both",
	target = "self",
	data = { amount = 6 },      -- hit points per tick
	uses = { statuses = { "regen" } },
	messages = {
		cast = "You have cast the %s spell, and will regenerate %d Hit Points for %d seconds.",
		cast_town = "You have cast the %s spell, and will regenerate %d Hit Points for %d seconds.",
	},
	cast = function(s)
		s.caster:afflict("regen", { ticks = s.power, amount = s.data.amount })
		s:say(s.in_fight and "cast" or "cast_town", s.name, s.data.amount, s:seconds(s.power))
	end,
}
