-- app/content/spells/fire_breath.lua :: a breath of fire: the breather gathers for a tick, then
-- the release (the stage below, as Solar Beam's) hits for a share of the caster's own attack
-- (armor ignored, so one spell serves a level 6 drake and a level 47 dragon) and sets the
-- target alight (the burning status: app/content/statuses/burning.lua). Learned by no class
-- by default: monsters cast it.
local function release(s)
	if s.target:immune_to("fire") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "fire"))
	local amount = math.max(3, s.caster.level // 5)   -- the burn grows with the breather's level
	if s.target:afflict("burning", { ticks = s.data.ticks, amount = amount }) then
		s:say("burn", s:seconds(s.data.ticks))
	end
end

return {
	name = "Fire Breath",
	description = "Draws a deep breath for a tick, then breathes fire for about half the caster's attack and sets the target alight. Some monsters are immune.",
	icon = "fire_breath",
	mp = 20,
	data = { min = 46, max = 55, ticks = 3 },   -- percent of the caster's attack; ticks the burn lasts
	uses = { statuses = { "charging", "burning" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s scorches the monster for %d damage.",
		burn = "The monster catches fire and burns for %d seconds.",
		immune = "Your %s rolls over the monster, but it is immune to fire.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster unleashes %s on you for %d damage.",
			burn = "You catch fire and burn for %d seconds.",
			immune = "The monster unleashes %s, but you are immune to fire.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
