-- app/content/statuses/marked.lua :: the bearer takes more damage from attacks (a weapon's
-- blow; not spells or allies, which never pass the damage hooks), in percent (the Hunter's
-- Mark spell: s.target:afflict("marked", { ticks = n, pct = 50 })). It lasts its ticks,
-- then fades.
return {
	name = "Marked",
	description = "Takes more damage (its percent) from weapon attacks for a while.",
	lore = [[
A hunter's mark, cut or painted onto a creature so that the next blows land harder. It is
a cheap trick and it works. Blades find the marked spot easily, and the mark fades after a
few turns whether or not anything has been hit. Spells and summoned allies ignore it.]],
	icon = "marked",
	kind = "harmful",
	ticks = 4,
	data = { pct = 50 },
	modify_damage_taken = function(t, damage)
		return damage + math.ceil(damage * (t.data.pct / 100))
	end,
}
