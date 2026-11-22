-- app/content/spells/enfeeble.lua :: the Enfeeble spell: the monster deals less damage for a
-- few turns (app/content/statuses/weakened.lua). Learned by no class by default.
-- learned: mage 10; warrior 48; paladin 12
local function cast(s)
	if not s.target:afflict("weakened", { turns = s.power, pct = s.data.pct }) then
		return s:say(s.target:ward("weakened") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s.power)
end

return {
	name = "Enfeeble",
	description = "Saps the monster's strength: it deals less damage for a few turns. Some monsters are immune.",
	lore = [[
Every village has a grandmother who can make a big farmhand sit down and wonder why he
feels so tired. Mages learn the trick from the books instead, and it works the same way: a
few quiet words, and the monster's blows land softer for the next few turns. It does not
stop a monster hitting, only hitting hard.]],
	icon = "enfeeble",
	mp = 8,
	power = 4,                  -- how many turns the weakness lasts
	data = { pct = 35 },        -- percent less damage the monster deals
	uses = { statuses = { "weakened" } },
	messages = {
		cast = "You have cast the %s spell. The monster is weakened for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You are weakened for %d turns.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
