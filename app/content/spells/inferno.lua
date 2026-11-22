-- app/content/spells/inferno.lua :: the Inferno spell: a fire that does not go out, burning the
-- monster for a large fixed amount on every tick of the clock
-- (app/content/statuses/burning.lua, as Ember does with smaller numbers).
-- learned: mage 88
local function cast(s)
	if s.target:immune_to("fire") then return s:say("immune", s.name) end
	if not s.target:afflict("burning", { ticks = s.power, amount = s.data.amount }) then
		return s:say(s.target:ward("burning") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Inferno",
	description = "Sets the monster ablaze: it burns for a great many hit points every 10 seconds. Some monsters are immune.",
	lore = [[
Ember is a spark in a haystack. Inferno is the haystack, the barn and the field behind it. A
Mage who casts it only has to stay out of the smoke while the target burns. The old
masters in Endworld say it was never meant for a fight: it was meant for clearing roads, and
roads are what it clears.]],
	icon = "inferno",
	mp = 45,
	power = 5,                  -- how many ticks the fire burns
	data = { amount = 40 },     -- hit points it burns away each tick
	uses = { statuses = { "burning" } },
	messages = {
		cast = "You have cast the %s spell. The monster burns for %d seconds.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You burn for %d seconds.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
