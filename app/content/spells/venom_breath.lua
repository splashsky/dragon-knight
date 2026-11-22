-- app/content/spells/venom_breath.lua :: a breath of poison (Fire Breath's kin: gathers for a
-- tick, then hits for a share of the caster's attack, armor ignored) that leaves the target
-- venomed (the venom status: it loses hit points and deals less damage). An area spell: the
-- release hits every foe of the breather and every object on the field (the rider goes to
-- creatures only). Learned by no class by default: monsters cast it.
local function release(s)
	local attack = s.caster.attack
	local venom = { ticks = s.data.ticks, min = s.data.venom_min, max = s.data.venom_max, pct = s.data.pct }
	for _, t in ipairs(s.targets) do
		if t:immune_to("poison") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "poison")) else s:say("hit", s.name, t.name, t:hurt(damage, "poison")) end
			if t.side ~= "object" and t:afflict("venom", venom) then
				if t.is_player then s:say("venom_you", s:seconds(s.data.ticks)) else s:say("venom", t.name, s:seconds(s.data.ticks)) end
			end
		end
	end
end

return {
	name = "Venom Breath",
	description = "Draws a deep breath for a tick, then breathes poison for about half the caster's attack over every foe and every object on the field; a creature hit is left venomed for 30 seconds. Some monsters are immune.",
	lore = [[
The green dragon breathes a sour cloud that sticks to armour and lungs alike. The
monster draws in a breath first, so the warning is the only hint you get, and anything
caught in the cloud coughs for half a minute. The venom thickens the blood, and the
victim hits a little softer until it wears off. Hunters in Hambry say the smell stays on
a man's coat for a week, and that the dragon knows where he has gone.]],
	icon = "venom_breath",
	area = true,                -- hits every foe and object (s.targets)
	mp = 20,
	-- percent of the caster's attack; the venom's ticks, hit points a tick and percent less damage dealt
	data = { min = 46, max = 55, ticks = 3, venom_min = 5, venom_max = 9, pct = 20 },
	uses = { statuses = { "charging", "venom" } },
	messages = {
		charge = "You have cast the %s spell, and draw a deep breath.",
		hit = "Your %s chokes the %s for %d damage.",
		venom = "The %s is venomed for %d seconds.",
		immune = "Your %s rolls over the %s, but it is immune to poison.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		venom_you = "You are venomed for %d seconds.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {
			charge = "The monster draws a deep breath for its %s.",
			hit = "The monster's %s chokes the %s for %d damage.",
			hit_you = "The monster unleashes %s on you for %d damage.",
			venom = "The %s is venomed for %d seconds.",
			venom_you = "You are venomed for %d seconds.",
			immune = "The monster's %s rolls over the %s, but it is immune to poison.",
			immune_you = "The monster unleashes %s, but you are immune to poison.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
