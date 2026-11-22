-- app/content/spells/scorch.lua :: a fire hotter than Ember's and cheaper than Inferno's: the
-- monster burns for a fixed amount on every tick of the clock (the burning status, as Ember
-- does with other numbers: 16 a tick sits between Ember's 7 and Inferno's 40).
-- learned: mage 45
local function cast(s)
	if s.target:immune_to("fire") then return s:say("immune", s.name) end
	if not s.target:afflict("burning", { ticks = s.power, amount = s.data.amount }) then
		return s:say(s.target:ward("burning") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Scorch",
	description = "Sets the monster alight with a fierce fire: it burns for 16 hit points every 10 seconds. Some monsters are immune.",
	icon = "scorch",
	mp = 24,
	power = 4,                  -- how many ticks the fire burns
	data = { amount = 16 },     -- hit points it burns away each tick
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
