-- app/content/spells/whiteout.lua :: a frost storm over the whole field (an area spell: every
-- foe and every object) that hits hard and puts a creature to sleep if the blow leaves it at
-- half its Hit Points or less (unless its ward stops it). Frost damage. Learned by no class
-- by default.
-- learned: mage 100
local function cast(s)
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		if t:immune_to("frost") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll((s.power / 6) * 5, s.power)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "frost")) else s:say("hit", s.name, t.name, t:hurt(damage, "frost")) end
			if t.side ~= "object" and t.hp * 2 <= t.maxhp and t:sleep(s.data.chance) then
				if t.is_player then s:say("asleep_you", s.name) else s:say("asleep", s.name, t.name) end
			end
		end
	end
end

return {
	name = "Whiteout",
	description = "A storm of frost over the whole field that hits every monster and every object hard, and sends a monster left at half its Hit Points or less to sleep. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Whiteout is the last thing an old Mage learns and the first thing a sensible one stops
casting in a closed room. The air goes grey, the snow comes in sideways, and a beast
caught in the middle of it tends to lie down. The Mages of Midworld say that a monster
which is still on its feet after a Whiteout has earned its place at the top of the list.]],
	icon = "whiteout",
	area = true,                -- hits every foe and object (s.targets)
	mp = 55,
	power = 180,                -- the most damage it deals
	data = { chance = 9 },      -- the chance in 15 that the sleep lasts each tick
	uses = { statuses = { "sleep" } },
	messages = {
		cast = "You have cast the %s spell, and a storm of frost sweeps the field.",
		hit = "The %s hits the %s for %d damage.",
		asleep = "The %s leaves the %s weakened, and it falls asleep.",
		immune = "The %s hits the %s, but it is immune to it.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		asleep_you = "The %s leaves you weakened, and you fall asleep.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {                    -- when a monster casts it
			cast = "The monster casts %s, and a storm of frost sweeps the field.",
			hit = "The %s hits the %s for %d damage.",
			hit_you = "The %s hits you for %d damage.",
			asleep = "The %s leaves the %s weakened, and it falls asleep.",
			asleep_you = "The %s leaves you weakened, and you fall asleep.",
			immune = "The %s hits the %s, but it is immune to it.",
			immune_you = "The %s hits you, but you are immune to it.",
		},
	},
	cast = cast,
}
