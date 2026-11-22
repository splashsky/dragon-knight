-- app/content/spells/mire.lua :: turns the ground to mud (the mud field, in place of the
-- ground's): earth grows and everyone is slowed.
-- learned: warrior 21
return {
	name = "Mire",
	description = "Turns the ground to deep mud for 50 seconds: earth hits 15% harder and everyone's dexterity is 20% lower.",
	lore = [[
Mud is a Warrior's friend, and Mire is the spell that makes it. The ground goes to deep,
sucking mud for a while, earth grows stronger in it, and everyone is clumsier on their
feet. Warriors learn it at twenty-one in the training yards of Roma, where the mud is
kept fresh for the purpose. The sergeants there say a fighter who makes the ground his
own does not have to be the strongest man on it.]],
	icon = "mire",
	mp = 12,
	power = 5,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "mud" } },
	messages = {
		cast = "You have cast the %s spell. The ground turns to mud for %d seconds.",
		already = "The ground is already mud. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. The ground turns to mud for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("mud") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("mud", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
