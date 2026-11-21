-- app/content/spells/war_cry.lua :: the War Cry spell (a Warrior's shout before the swing).
-- learned: warrior 3
-- A scripted content file (docs/APP.md "Scripting spells and items").
return {
	name = "War Cry",
	description = "Increases the damage you deal and reduces the damage you take a little, until the end of the fight.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Every village has a man who can shout loud enough to wake the dead, and most of them
learned it from a sergeant. The cry is nothing but breath and noise, but a Warrior who
starts a fight roaring tends to finish it with his blood up. It costs a little wind and
a little magic, and it steadies the shoulders as well.]],
	mp = 6,
	power = 8,                  -- percent more damage
	data = { defense = 8 },     -- percent less damage taken
	target = "self",
	messages = {
		cast = "You have cast the %s spell, will deal %d%% more damage and take %d%% less until the end of this fight.",
	},
	cast = function(s)
		s.caster:buff("damage", s.power)
		s.caster:buff("defense", s.data.defense)
		s:say("cast", s.name, s.power, s.data.defense)
	end,
}
