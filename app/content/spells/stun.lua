-- app/content/spells/stun.lua :: the Stun spell (a hard pommel to the head, not a lullaby).
-- learned: warrior 17
-- Uses the same sleep status as Sleep, with a low chance: the monster only stays dazed for
-- a turn or so, which is enough to get in a second blow.
return {
	name = "Stun",
	description = "Dazes the monster for a turn or two. Some monsters are immune.",
	lore = [[
Not sleep, whatever the mages say. A Warrior who has taken a hard blow with the flat of
a shield knows the look: the eyes go somewhere else for a heartbeat, and the feet forget
what they were doing. It lasts only a turn or two, so it is a poor reason to stop
fighting and an excellent one to swing again.]],
	icon = "stun",
	mp = 6,
	power = 2,                  -- the chance in 15 that it stays dazed each tick
	messages = {
		asleep = "You have cast the %s spell. The monster is stunned.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {                    -- when a monster casts it
			asleep = "The monster casts %s on you. You are stunned.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = function(s)
		if not s.target:sleep(s.power) then
			return s:say(s.target:ward("sleep") == 100 and "immune" or "resisted", s.name)
		end
		s:say("asleep", s.name)
	end,
}
