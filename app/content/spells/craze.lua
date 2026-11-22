-- app/content/spells/craze.lua :: the Craze spell (the original game's spell 14).
local function cast(s)
	s.caster:buff("damage", s.power)
	s:say("cast", s.name, s.power)
end

return {
	name = "Craze",
	description = "Increases the damage you deal until the end of the fight.",
	lore = [[
A cheap trick taught in the taverns of Roma, where fighters use it before a brawl. It makes
the caster angrier and sloppier, and the blows land a little harder for it. Priests dislike
it, but nobody has ever asked a Warrior to stop.]],
	icon = "craze",
	mp = 10,
	power = 10,                 -- percent more damage
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% damage until the end of this fight.",
	},
	cast = cast,
}
