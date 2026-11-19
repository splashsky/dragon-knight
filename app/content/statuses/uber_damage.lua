-- app/content/statuses/uber_damage.lua :: more damage dealt, in percent (the original
-- game's "uber damage" of the Craze, Rage and Fury spells; id 2). s.caster:buff("damage",
-- pct) puts it on (the same as s.caster:afflict("uber_damage", { pct = n })). It lasts
-- until the end of the fight.
local function more(t, damage)
	return damage + math.ceil(damage * (t.data.pct / 100))
end

return {
	name = "Damage Up",
	description = "Deals more damage (its percent) until the end of the fight.",
	kind = "helpful",
	data = { pct = 0 },
	modify_damage_dealt = more,
}
