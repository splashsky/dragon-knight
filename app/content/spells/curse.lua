-- app/content/spells/curse.lua :: the Curse spell: a heavy weakness, the monster deals far less
-- damage for a while (app/content/statuses/weakened.lua, as Enfeeble does with
-- smaller numbers).
-- learned: mage 73; warrior 94; paladin 80
local function cast(s)
	if s.target:immune_to("shadow") then return s:say("immune", s.name) end
	if not s.target:afflict("weakened", { ticks = s.power, pct = s.data.pct }) then
		return s:say(s.target:ward("weakened") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Curse",
	description = "Lays a heavy weakness on the monster: it deals far less damage for a while. Some monsters are immune.",
	lore = [[
Most spells ask the world for a favour. A curse only asks it to look away for a moment, and
the monster's arm forgets how hard it was swinging. It is easy to cast and hard to cast
well, and the priests of Gilead will not say who taught it to them. Against something that
hits for three hundred a turn, nobody is shy about using it.]],
	icon = "curse",
	mp = 30,
	power = 5,                  -- how many ticks the weakness lasts
	data = { pct = 50 },        -- percent less damage the monster deals
	uses = { statuses = { "weakened" } },
	messages = {
		cast = "You have cast the %s spell. The monster is cursed for %d seconds.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You are cursed for %d seconds.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
