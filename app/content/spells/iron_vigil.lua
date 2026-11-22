-- app/content/spells/iron_vigil.lua :: the Iron Vigil spell (a shield raised and a wound bound at once).
-- learned: paladin 48
-- A defense buff until the end of the fight, plus a heal that is a share of maximum HP.
return {
	name = "Iron Vigil",
	description = "Reduces the damage you take until the end of the fight, and restores a share of your maximum hit points.",
	lore = [[
Keeping watch through the night is a Paladin's oldest duty, and the vigil prayer is
said standing up, so the knees do not give out before the dawn. Those who have kept a
long one say the iron in the blood is real: the blows land softer and the cuts stop
oozing. The priests at Gilead say it is faith; the mercenaries who drink with them say
it is the prayer and the cold, and that they will take either.]],
	icon = "iron_vigil",
	mp = 28,
	power = 35,                 -- percent less damage taken
	data = { heal = 12 },       -- percent of your maximum HP it restores
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will take %d%% less damage until this fight ends. You gained %d Hit Points.",
	},
	cast = function(s)
		s.caster:buff("defense", s.power)
		local healed = s.caster:heal("hp", math.floor(s.caster.maxhp * s.data.heal / 100))
		s:say("cast", s.name, s.power, healed)
	end,
}
