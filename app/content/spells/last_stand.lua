-- app/content/spells/last_stand.lua :: the Last Stand spell (the Warrior who will not step back).
-- learned: warrior 42; paladin 96
-- Only works when the caster is at a quarter of maximum HP or less: a strong damage buff
-- and a defense buff together, until the end of the fight.
return {
	name = "Last Stand",
	description = "When you are badly hurt, increases the damage you deal and reduces the damage you take until the end of the fight.",
	lore = [[
Named after a pass in the hills where forty men held a road for a day and a night, and
where most of them are still buried. The survivors did not talk about the pass much, but
they taught their recruits one rule: when you are at the end of
your rope, stop looking for the way out and tie the knot. It does not work at full
health, which is the point; a man who casts it early has simply misjudged the fight.]],
	mp = 10,
	power = 50,                 -- percent more damage dealt
	data = { guard = 25 },      -- percent less damage taken
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will deal %d%% more damage and take %d%% less until this fight ends.",
		not_low = "You are not hurt enough for %s yet. Fight on a little longer.",
	},
	-- refused (costs nothing) while above a quarter of maximum HP
	can_cast = function(s)
		if s.caster.hp * 4 > s.caster.maxhp then return s:refuse("not_low", s.name) end
	end,
	cast = function(s)
		s.caster:buff("damage", s.power)
		s.caster:buff("defense", s.data.guard)
		s:say("cast", s.name, s.power, s.data.guard)
	end,
}
