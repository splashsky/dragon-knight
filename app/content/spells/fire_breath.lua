-- app/content/spells/fire_breath.lua :: a breath of fire: the breather gathers for a tick, then
-- the release (the stage below, as Solar Beam's) hits for a share of the caster's own attack
-- (armor ignored, so one spell serves a level 6 drake and a level 47 dragon) and sets the
-- target alight (the burning status: app/content/statuses/burning.lua). An area spell: the
-- release hits every foe of the breather and every object on the field (it lights a barrel
-- and burns up a hive). Learned by no class by default: monsters cast it.
local function release(s)
	local attack = s.caster.attack
	local amount = math.max(3, s.caster.level // 5)   -- the burn grows with the breather's level
	for _, t in ipairs(s.targets) do
		if t:immune_to("fire") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "fire")) else s:say("hit", s.name, t.name, t:hurt(damage, "fire")) end
			if t:afflict("burning", { ticks = s.data.ticks, amount = amount }) then
				if t.is_player then s:say("burn_you", s:seconds(s.data.ticks)) else s:say("burn", t.name, s:seconds(s.data.ticks)) end
			end
		end
	end
end

return {
	name = "Fire Breath",
	description = "Draws a deep breath for a tick, then breathes fire for about half the caster's attack over every foe and every object on the field, and sets them alight. Some monsters are immune.",
	lore = [[
A drakemal puffs smoke and singes a coat. A fire wyrm draws a long breath first, and the
warning lasts one whole turn, long enough for the wise to get behind something solid.
The fire sticks to the target and burns on for a few turns, and the higher the
breather's level, the hotter the burn. Wardens of Roma have seen a red dragon's fire run
down a cave wall, and they do not argue about how long the warning took.]],
	icon = "fire_breath",
	area = true,                -- hits every foe and object (s.targets)
	mp = 20,
	data = { min = 46, max = 55, ticks = 3 },   -- percent of the caster's attack; ticks the burn lasts
	uses = { statuses = { "charging", "burning" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s scorches the %s for %d damage.",
		burn = "The %s catches fire and burns for %d seconds.",
		immune = "Your %s rolls over the %s, but it is immune to fire.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		burn_you = "You catch fire and burn for %d seconds.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster's %s scorches the %s for %d damage.",
			hit_you = "The monster unleashes %s on you for %d damage.",
			burn = "The %s catches fire and burns for %d seconds.",
			burn_you = "You catch fire and burn for %d seconds.",
			immune = "The monster's %s rolls over the %s, but it is immune to fire.",
			immune_you = "The monster unleashes %s, but you are immune to fire.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
