-- app/content/spells/frost_breath.lua :: a breath of frost (Fire Breath's mirror: gathers for
-- a tick, then hits for a share of the caster's attack, armor ignored) whose cold numbs the
-- target's arms: it deals less damage for a short while (the weakened status). An area spell:
-- the release hits every foe of the breather and every object on the field (the rider goes
-- to creatures only). Learned by no class by default: monsters cast it.
local function release(s)
	local attack = s.caster.attack
	for _, t in ipairs(s.targets) do
		if t:immune_to("frost") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "frost")) else s:say("hit", s.name, t.name, t:hurt(damage, "frost")) end
			if t.side ~= "object" and t:afflict("weakened", { ticks = s.data.ticks, pct = s.data.pct }) then
				if t.is_player then s:say("numb_you", s:seconds(s.data.ticks)) else s:say("numb", t.name, s:seconds(s.data.ticks)) end
			end
		end
	end
end

return {
	name = "Frost Breath",
	description = "Draws a deep breath for a tick, then breathes frost for about half the caster's attack over every foe and every object on the field; the cold numbs the arms, so a creature hit deals 25% less damage for 20 seconds. Some monsters are immune.",
	lore = [[
Frost is the fire's cold cousin, and it is worse for the fighter who has to keep his
feet. The monster draws a deep breath for a turn first, and the frost that comes out
numbs the arms, so the numbed target hits for a quarter less for a short while. Blue
dragons in the Kalle peaks use it, and so do the frost wyrms in the snow above Narcissa.
Carters say the snow goes quiet just before the breath comes.]],
	icon = "frost_breath",
	area = true,                -- hits every foe and object (s.targets)
	mp = 20,
	data = { min = 46, max = 55, ticks = 2, pct = 25 },   -- percent of the caster's attack; ticks and percent less damage dealt
	uses = { statuses = { "charging", "weakened" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s chills the %s for %d damage.",
		numb = "The cold numbs the %s's arms for %d seconds.",
		immune = "Your %s rolls over the %s, but it is immune to frost.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		numb_you = "The cold numbs your arms for %d seconds.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster's %s chills the %s for %d damage.",
			hit_you = "The monster unleashes %s on you for %d damage.",
			numb = "The cold numbs the %s's arms for %d seconds.",
			numb_you = "The cold numbs your arms for %d seconds.",
			immune = "The monster's %s rolls over the %s, but it is immune to frost.",
			immune_you = "The monster unleashes %s, but you are immune to frost.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
