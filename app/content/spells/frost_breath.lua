-- app/content/spells/frost_breath.lua :: a breath of frost (Fire Breath's mirror: gathers for
-- a tick, then hits for a share of the caster's attack, armor ignored) whose cold numbs the
-- target's arms: it deals less damage for a short while (the weakened status). Learned by no
-- class by default: monsters cast it.
local function release(s)
	if s.target:immune_to("frost") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "frost"))
	if s.target:afflict("weakened", { ticks = s.data.ticks, pct = s.data.pct }) then
		s:say("numb", s:seconds(s.data.ticks))
	end
end

return {
	name = "Frost Breath",
	description = "Draws a deep breath for a tick, then breathes frost for about half the caster's attack; the cold numbs the arms, so the target deals 25% less damage for 20 seconds. Some monsters are immune.",
	lore = [[
Frost is the fire's cold cousin, and it is worse for the fighter who has to keep his
feet. The monster draws a deep breath for a turn first, and the frost that comes out
numbs the arms, so the numbed target hits for a quarter less for a short while. Blue
dragons in the Kalle peaks use it, and so do the frost wyrms in the snow above Narcissa.
Carters say the snow goes quiet just before the breath comes.]],
	icon = "frost_breath",
	mp = 20,
	data = { min = 46, max = 55, ticks = 2, pct = 25 },   -- percent of the caster's attack; ticks and percent less damage dealt
	uses = { statuses = { "charging", "weakened" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s chills the monster for %d damage.",
		numb = "The cold numbs the monster's arms for %d seconds.",
		immune = "Your %s rolls over the monster, but it is immune to frost.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster unleashes %s on you for %d damage.",
			numb = "The cold numbs your arms for %d seconds.",
			immune = "The monster unleashes %s, but you are immune to frost.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
