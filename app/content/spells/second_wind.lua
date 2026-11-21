-- app/content/spells/second_wind.lua :: the Second Wind spell (a soldier's breath found in the middle of a fight).
-- learned: warrior 36
-- Fight only. The heal is a share of maximum HP (up to a limit), so it grows as the Warrior does.
return {
	name = "Second Wind",
	description = "Restores a share of your maximum hit points, in a fight only.",
	lore = [[
A sergeant's trick that nobody writes down: when the line is wavering, you stop, plant
your feet, and take three long breaths before the next swing. It works because a tired
man who believes he can go on usually can, for a while. Recruits are told it is a gift
from the gods; veterans know it is mostly stubbornness, and that it does not work twice
in one fight.]],
	mp = 14,
	power = 25,                 -- percent of your maximum HP it restores
	data = { cap = 60 },        -- the most HP it restores
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		full = "Your Hit Points are already full. There is no need to catch your breath.",
	},
	-- refused (costs nothing) at full HP
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp then return s:refuse("full") end
	end,
	cast = function(s)
		s:say("cast", s.name, s.caster:heal("hp", math.min(s.data.cap, math.floor(s.caster.maxhp * s.power / 100))))
	end,
}
