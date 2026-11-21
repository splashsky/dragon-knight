-- app/content/spells/cleanse.lua :: the Cleanse spell: cures the harmful statuses (poison,
-- sleep, ...) and restores no hit points. Learned by no class by default.
-- learned: mage 27; warrior 88; paladin 3
return {
	name = "Cleanse",
	description = "Cures poison, sleep and the other harmful effects, in a fight or out of it.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Poison, sleep and the rest of the harmful effects are why most young Paladins carry
antidotes they can't afford. Cleanse does the same job from a short prayer. For three
MP it costs less than the antidote the market in Roma charges, and it never runs out
on the road.]],
	mp = 3,
	power = 0,                  -- unused: it cures every harmful status
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and cured the harmful effects.",
		none = "Nothing harmful ails you. Please go back and try again.",
		none_town = "Nothing harmful ails you now.",
		enemy = {
			cast = "The monster casts %s and shakes off what ailed it.",
		},
	},
	-- refused (costs nothing) when no harmful status is on the caster
	can_cast = function(s)
		if #s.caster:statuses("harmful") == 0 then return s:refuse(s.in_fight and "none" or "none_town") end
	end,
	cast = function(s)
		s.caster:cure("harmful")
		s:say("cast", s.name)
	end,
}
