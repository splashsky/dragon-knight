-- app/content/statuses/weakened.lua :: the bearer deals less damage, in percent (the Enfeeble
-- spell puts it on a monster: s.target:afflict("weakened", { turns = n, pct = 25 })). It
-- lasts its turns, then wears off.
return {
	name = "Weakened",
	description = "Deals less damage (its percent) for a few turns.",
	kind = "harmful",
	turns = 3,
	data = { pct = 35 },
	modify_damage_dealt = function(t, damage)
		return damage - math.floor(damage * (t.data.pct / 100))
	end,
}
