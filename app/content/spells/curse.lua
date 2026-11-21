-- app/content/spells/curse.lua :: the Curse spell: a heavy weakness, the monster deals far less
-- damage for a few turns (app/content/statuses/weakened.lua, as Enfeeble does with
-- smaller numbers).
-- learned: mage 73; warrior 94; paladin 80
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	s.target:afflict("weakened", { turns = s.power, pct = s.data.pct })
	s:say("cast", s.name, s.power)
end

return {
	name = "Curse",
	description = "Lays a heavy weakness on the monster: it deals far less damage for a few turns. Some monsters are immune.",
	lore = [[
Most spells ask the world for a favour. A curse only asks it to look away for a moment, and
the monster's arm forgets how hard it was swinging. It is easy to cast and hard to cast
well, and the priests of Gilead will not say who taught it to them. Against something that
hits for three hundred a turn, nobody is shy about using it.]],
	mp = 30,
	power = 5,                  -- how many turns the weakness lasts
	data = { pct = 50 },        -- percent less damage the monster deals
	uses = { statuses = { "weakened" } },
	messages = {
		cast = "You have cast the %s spell. The monster is cursed for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			cast = "The monster casts %s. You are cursed for %d turns.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
