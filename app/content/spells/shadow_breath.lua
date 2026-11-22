-- app/content/spells/shadow_breath.lua :: a breath of darkness (Fire Breath's kin: gathers for
-- a tick, then hits for a share of the caster's attack, armor ignored) that leaves the target
-- withering (the withering status: the caster gains what the target loses). An area spell:
-- the release hits every foe of the breather and every object on the field (the rider goes
-- to creatures only: an object has nothing to drain). Learned by no class by default:
-- monsters cast it.
local function release(s)
	local attack = s.caster.attack
	local wither = { ticks = s.data.ticks, min = s.data.wither_min, max = s.data.wither_max }
	for _, t in ipairs(s.targets) do
		if t:immune_to("shadow") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "shadow")) else s:say("hit", s.name, t.name, t:hurt(damage, "shadow")) end
			if t.side ~= "object" and t:afflict("withering", wither) then
				if t.is_player then s:say("wither_you", s:seconds(s.data.ticks)) else s:say("wither", t.name, s:seconds(s.data.ticks)) end
			end
		end
	end
end

return {
	name = "Shadow Breath",
	description = "Draws a deep breath for a tick, then breathes darkness for about half the caster's attack over every foe and every object on the field; a creature hit withers for 30 seconds, and the caster gains what it loses. Some monsters are immune.",
	lore = [[
A breath of darkness does not scorch. It fills the mouth of the one it hits and drains
the life out of it for a while, and the breather takes what the victim loses. The
monster draws a deep breath for a turn first, and the gathering darkness is the warning,
though it is hard to see in the dark. Dark dragons and shadow dragons use it, and the
watchmen of Narcissa say the weakness that follows is worse than the bite.]],
	icon = "shadow_breath",
	area = true,                -- hits every foe and object (s.targets)
	mp = 20,
	-- percent of the caster's attack; the withering's ticks and hit points drained a tick
	data = { min = 46, max = 55, ticks = 3, wither_min = 10, wither_max = 16 },
	uses = { statuses = { "charging", "withering" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s engulfs the %s for %d damage.",
		wither = "The %s withers for %d seconds.",
		immune = "Your %s rolls over the %s, but it is immune to shadow.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		wither_you = "You wither for %d seconds.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster's %s engulfs the %s for %d damage.",
			hit_you = "The monster unleashes %s on you for %d damage.",
			wither = "The %s withers for %d seconds.",
			wither_you = "You wither for %d seconds.",
			immune = "The monster's %s rolls over the %s, but it is immune to shadow.",
			immune_you = "The monster unleashes %s, but you are immune to shadow.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
