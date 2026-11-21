-- app/content/statuses/uber_defense.lua :: less damage taken, in percent (the original
-- game's "uber defense" of the Ward, Fend and Barrier spells; id 3). s.caster:buff(
-- "defense", pct) puts it on. It lasts until the end of the fight.
return {
	name = "Defense Up",
	description = "Takes less damage (its percent) until the end of the fight.",
	lore = [[
A ward laid over the body, a shimmer that blunts blows for the rest of the fight. Priests
of Midworld teach it as a plain prayer and charge little for it. It does not stop a blow
outright; it only makes each one smaller, and the difference adds up over a long fight
with a big monster.]],
	kind = "helpful",
	data = { pct = 0 },
	modify_damage_taken = function(t, damage)
		return damage - math.ceil(damage * (t.data.pct / 100))
	end,
}
