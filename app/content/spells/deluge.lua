-- app/content/spells/deluge.lua :: a wall of water: it hits for a share of the caster's own
-- attack (armor ignored) and brings a downpour over the battlefield (the downpour field, in
-- place of the sky's), where lightning is strong and no fire can catch. Learned by no class
-- by default: monsters cast it.
local function cast(s)
	if s.target:immune_to("water") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "water"))
	if s:field("downpour", { ticks = s.power }) then s:say("downpour", s:seconds(s.power)) end
end

return {
	name = "Deluge",
	description = "Floods the monster for about a third of the caster's attack, whatever the armor, and brings a downpour over the battlefield for 40 seconds. Some monsters are immune.",
	icon = "deluge",
	mp = 30,
	power = 4,                  -- how many ticks the downpour lasts
	data = { min = 33, max = 40 },   -- percent of the caster's attack
	uses = { fields = { "downpour" } },
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		downpour = "A downpour hammers the field for %d seconds.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			hit = "The monster casts %s on you for %d damage.",
			downpour = "A downpour hammers the field for %d seconds.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
