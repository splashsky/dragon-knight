-- app/content/spells/ember.lua :: the Ember spell: sets the monster on fire, so it burns for a
-- fixed amount at the end of each of its turns (app/content/statuses/burning.lua). Learned
-- by no class by default.
-- learned: mage 19
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	s.target:afflict("burning", { turns = s.power, amount = s.data.amount })
	s:say("cast", s.name, s.power)
end

return {
	name = "Ember",
	description = "Sets the monster alight: it burns for a few hit points every turn. Some monsters are immune.",
	lore = [[
Mages who have been burned once never forget the first lesson: fire keeps working after the
spell is done. An Ember leaves a small, stubborn flame on the target that eats a few hit
points every turn, the way a cook's oil spatter keeps stinging the wrist. Hunters in Roma
swear it also makes a wolf think twice about coming back.]],
	icon = "ember",
	mp = 10,
	power = 4,                  -- how many turns the fire burns
	data = { amount = 7 },      -- hit points it burns away each turn
	uses = { statuses = { "burning" } },
	messages = {
		cast = "You have cast the %s spell. The monster burns for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			cast = "The monster casts %s. You burn for %d turns.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
