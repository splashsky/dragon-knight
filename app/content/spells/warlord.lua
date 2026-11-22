-- app/content/spells/warlord.lua :: the Warlord spell (the command voice that carries across a field).
-- learned: warrior 100
-- A large damage buff until the end of the fight, plus a heal that is a share of maximum HP.
return {
	name = "Warlord",
	description = "Greatly increases the damage you deal and restores a share of your maximum hit points, until the end of the fight.",
	lore = [[
Only a handful of men in the realm have earned the name, and most of them do not like
it. The voice has to carry across a muddy field in a gale, and it has to make a line of
frightened farmers take one more step. The cost is hoarse throats and a few swallowed
bruises, but the men who hear it say they stopped feeling the wounds for the length of
the charge.]],
	icon = "warlord",
	mp = 40,
	power = 75,                 -- percent more damage dealt
	data = { heal = 25 },       -- percent of your maximum HP it restores
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will deal %d%% more damage until this fight ends. You gained %d Hit Points.",
	},
	cast = function(s)
		s.caster:buff("damage", s.power)
		local healed = s.caster:heal("hp", math.floor(s.caster.maxhp * s.data.heal / 100))
		s:say("cast", s.name, s.power, healed)
	end,
}
