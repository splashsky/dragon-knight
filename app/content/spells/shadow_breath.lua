-- app/content/spells/shadow_breath.lua :: a breath of darkness (Fire Breath's kin: gathers for
-- a tick, then hits for a share of the caster's attack, armor ignored) that leaves the target
-- withering (the withering status: the caster gains what the target loses). Learned by no
-- class by default: monsters cast it.
local function release(s)
	if s.target:immune_to("shadow") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "shadow"))
	local wither = { ticks = s.data.ticks, min = s.data.wither_min, max = s.data.wither_max }
	if s.target:afflict("withering", wither) then s:say("wither", s:seconds(s.data.ticks)) end
end

return {
	name = "Shadow Breath",
	description = "Draws a deep breath for a tick, then breathes darkness for about half the caster's attack; the target withers for 30 seconds, and the caster gains what it loses. Some monsters are immune.",
	lore = [[
A breath of darkness does not scorch. It fills the mouth of the one it hits and drains
the life out of it for a while, and the breather takes what the victim loses. The
monster draws a deep breath for a turn first, and the gathering darkness is the warning,
though it is hard to see in the dark. Dark dragons and shadow dragons use it, and the
watchmen of Narcissa say the weakness that follows is worse than the bite.]],
	icon = "shadow_breath",
	mp = 20,
	-- percent of the caster's attack; the withering's ticks and hit points drained a tick
	data = { min = 46, max = 55, ticks = 3, wither_min = 10, wither_max = 16 },
	uses = { statuses = { "charging", "withering" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s engulfs the monster for %d damage.",
		wither = "The monster withers for %d seconds.",
		immune = "Your %s rolls over the monster, but it is immune to shadow.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster unleashes %s on you for %d damage.",
			wither = "You wither for %d seconds.",
			immune = "The monster unleashes %s, but you are immune to shadow.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
