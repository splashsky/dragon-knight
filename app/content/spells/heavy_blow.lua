-- app/content/spells/heavy_blow.lua :: a telegraphed blow: the caster draws back for a tick,
-- then the release hits for a share of its own attack (neutral, armor ignored, like the
-- breaths). The knights', giants' and daemons' special, and the wyverns' dive. Learned by no
-- class by default: monsters cast it.
local function release(s)
	if s.target:immune_to("neutral") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "neutral"))
end

return {
	name = "Heavy Blow",
	description = "Draws back for a tick, then strikes for more than half the caster's attack, whatever the armor. Some monsters are immune.",
	icon = "heavy_blow",
	mp = 15,
	data = { min = 50, max = 60 },   -- percent of the caster's attack
	uses = { statuses = { "charging" } },
	messages = {
		charge = "You have cast the %s spell, and draw back for a mighty blow.",
		hit = "Your %s lands on the monster for %d damage.",
		immune = "Your %s lands, but the monster is immune to it.",
		enemy = {
			charge = "The monster draws back for a mighty blow.",
			hit = "The monster's %s lands on you for %d damage.",
			immune = "The monster's %s lands, but you are immune to it.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
