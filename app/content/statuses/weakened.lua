-- app/content/statuses/weakened.lua :: the bearer deals less damage, in percent (the Enfeeble
-- spell puts it on a monster: s.target:afflict("weakened", { turns = n, pct = 25 })). It
-- lasts its turns, then wears off.
return {
	name = "Weakened",
	description = "Deals less damage (its percent) for a few turns.",
	lore = [[
The limbs go heavy and the grip goes loose, from a chant that drains the strength out of a
body. The creature is still on its feet and still means harm, but its blows land softer
for a few turns. Warriors who have been enfeebled say it feels like hitting through wet
sand, and they are glad when it wears off.]],
	kind = "harmful",
	turns = 3,
	data = { pct = 35 },
	modify_damage_dealt = function(t, damage)
		return damage - math.floor(damage * (t.data.pct / 100))
	end,
}
