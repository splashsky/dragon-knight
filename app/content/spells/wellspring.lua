-- app/content/spells/wellspring.lua :: the Wellspring spell: a cheap magic points top-up,
-- refused while the caster still has more than half of its MP. Learned by no class by
-- default.
-- learned: mage 21; warrior 54; paladin 76
return {
	name = "Wellspring",
	description = "Restores some magic points, but only while the caster is at half or less of its magic points.",
	lore = [[
A Mage's mana runs out in the middle of a fight more often than any of them will admit.
Wellspring is a small, cheap prayer of the kind Mages teach each other over a bad cup of
tea, not one that comes from a book. It only works while there is room for it: with more
than half of your Magic Points left it is refused, and that costs you nothing.]],
	mp = 3,
	power = 15,                 -- percent of the maximum MP it restores
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and gained %d Magic Points.",
		full = "You still have more than half your Magic Points. Please go back and try again.",
		full_town = "You still have more than half your Magic Points. You don't need to use Wellspring now.",
		enemy = {
			cast = "The monster casts %s and gains %d Magic Points.",
		},
	},
	-- refused (costs nothing) with more than half of the MP left
	can_cast = function(s)
		if s.caster.mp * 2 > s.caster.maxmp then return s:refuse(s.in_fight and "full" or "full_town") end
	end,
	cast = function(s)
		s:say("cast", s.name, s.caster:heal("mp", math.floor(s.caster.maxmp * s.power / 100)))
	end,
}
