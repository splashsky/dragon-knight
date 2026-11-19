-- app/content/statuses/uber_defense.lua :: less damage taken, in percent (the original
-- game's "uber defense" of the Ward, Fend and Barrier spells; id 3). s.caster:buff(
-- "defense", pct) puts it on. It lasts until the end of the fight.
return {
	name = "Defense Up",
	description = "Takes less damage (its percent) until the end of the fight.",
	kind = "helpful",
	data = { pct = 0 },
	modify_damage_taken = function(t, damage)
		return damage - math.ceil(damage * (t.data.pct / 100))
	end,
}
