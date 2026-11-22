-- app/content/spells/venom_breath.lua :: a breath of poison (Fire Breath's kin: gathers for a
-- tick, then hits for a share of the caster's attack, armor ignored) that leaves the target
-- venomed (the venom status: it loses hit points and deals less damage). Learned by no class
-- by default: monsters cast it.
local function release(s)
	if s.target:immune_to("poison") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "poison"))
	local venom = { ticks = s.data.ticks, min = s.data.venom_min, max = s.data.venom_max, pct = s.data.pct }
	if s.target:afflict("venom", venom) then s:say("venom", s:seconds(s.data.ticks)) end
end

return {
	name = "Venom Breath",
	description = "Draws a deep breath for a tick, then breathes poison for about half the caster's attack; the target is left venomed for 30 seconds. Some monsters are immune.",
	lore = [[
The green dragon breathes a sour cloud that sticks to armour and lungs alike. The
monster draws in a breath first, so the warning is the only hint you get, and anything
caught in the cloud coughs for half a minute. The venom thickens the blood, and the
victim hits a little softer until it wears off. Hunters in Hambry say the smell stays on
a man's coat for a week, and that the dragon knows where he has gone.]],
	icon = "venom_breath",
	mp = 20,
	-- percent of the caster's attack; the venom's ticks, hit points a tick and percent less damage dealt
	data = { min = 46, max = 55, ticks = 3, venom_min = 5, venom_max = 9, pct = 20 },
	uses = { statuses = { "charging", "venom" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s chokes the monster for %d damage.",
		venom = "The monster is venomed for %d seconds.",
		immune = "Your %s rolls over the monster, but it is immune to poison.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster unleashes %s on you for %d damage.",
			venom = "You are venomed for %d seconds.",
			immune = "The monster unleashes %s, but you are immune to poison.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
