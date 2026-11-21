-- app/content/statuses/marked.lua :: the bearer takes more damage from attacks (a weapon's
-- blow; not spells or allies, which never pass the damage hooks), in percent (the Hunter's
-- Mark spell: s.target:afflict("marked", { turns = n, pct = 50 })). It lasts its turns,
-- then fades.
return {
	name = "Marked",
	description = "Takes more damage (its percent) from weapon attacks for a few turns.",
	kind = "harmful",
	turns = 4,
	data = { pct = 50 },
	modify_damage_taken = function(t, damage)
		return damage + math.ceil(damage * (t.data.pct / 100))
	end,
}
