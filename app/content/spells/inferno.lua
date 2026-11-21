-- app/content/spells/inferno.lua :: the Inferno spell: a fire that does not go out, burning the
-- monster for a large fixed amount at the end of each of its turns
-- (app/content/statuses/burning.lua, as Ember does with smaller numbers).
-- learned: mage 88
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	s.target:afflict("burning", { turns = s.power, amount = s.data.amount })
	s:say("cast", s.name, s.power)
end

return {
	name = "Inferno",
	description = "Sets the monster ablaze: it burns for a great many hit points every turn. Some monsters are immune.",
	lore = [[
Ember is a spark in a haystack. Inferno is the haystack, the barn and the field behind it. A
Mage who casts it only has to stay out of the smoke while the target burns. The old
masters in Endworld say it was never meant for a fight: it was meant for clearing roads, and
roads are what it clears.]],
	mp = 45,
	power = 5,                  -- how many turns the fire burns
	data = { amount = 40 },     -- hit points it burns away each turn
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
