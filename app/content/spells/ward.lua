-- app/content/spells/ward.lua :: the Ward spell (the original game's spell 17).
return {
	name = "Ward",
	description = "Reduces the damage you take until the end of the fight.",
	lore = [[
Ward is the first defence a Mage learns, a thin shimmer around the body that turns a blow
aside now and then. It will not save a caster from a dragon, but it has spared more than one
apprentice a bruise. Guards on the road out of Midworld are taught it before they are given
a spear.]],
	mp = 10,
	power = 10,                 -- percent less damage taken
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% defense until the end of this fight.",
	},
	cast = function(s)
		s.caster:buff("defense", s.power)
		s:say("cast", s.name, s.power)
	end,
}
