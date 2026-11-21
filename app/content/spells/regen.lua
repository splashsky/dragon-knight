-- app/content/spells/regen.lua :: the caster regenerates hit points every turn, or every
-- move on the map when cast outside a fight (the status regen is a world status too).
-- Learned by no class by default.
return {
	name = "Regen",
	description = "Recovers hit points every turn of a fight, or every move outside one.",
	lore = [[
Regen is a slow mending that Mages in Narcissa picked up from watching the town's cats, which
heal scratches overnight. It closes small wounds a little each turn, in a fight or on the road.
It helps on long walks and long fights, but it will not close a deep cut.]],
	mp = 8,
	power = 5,                  -- turns (moves outside fights)
	usable_in = "both",
	target = "self",
	data = { amount = 6 },      -- hit points per turn
	uses = { statuses = { "regen" } },
	messages = {
		cast = "You have cast the %s spell, and will regenerate %d Hit Points for %d turns.",
		cast_town = "You have cast the %s spell, and will regenerate %d Hit Points for the next %d moves.",
	},
	cast = function(s)
		s.caster:afflict("regen", { turns = s.power, amount = s.data.amount })
		s:say(s.in_fight and "cast" or "cast_town", s.name, s.data.amount, s.power)
	end,
}
