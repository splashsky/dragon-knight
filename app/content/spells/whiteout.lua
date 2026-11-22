-- app/content/spells/whiteout.lua :: a frost storm that hits hard and puts the monster to
-- sleep if the blow leaves it at half its Hit Points or less (unless its ward stops it).
-- Frost damage. Learned by no class by default.
-- learned: mage 100
local function cast(s)
	if s.target:immune_to("frost") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s:say("hit", s.name, s.target:hurt(damage, "frost"))
	if s.target.hp * 2 <= s.target.maxhp and s.target:sleep(s.data.chance) then s:say("asleep", s.name) end
end

return {
	name = "Whiteout",
	description = "A storm of frost that hits hard, and sends a monster left at half its Hit Points or less to sleep. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Whiteout is the last thing an old Mage learns and the first thing a sensible one stops
casting in a closed room. The air goes grey, the snow comes in sideways, and a beast
caught in the middle of it tends to lie down. The Mages of Midworld say that a monster
which is still on its feet after a Whiteout has earned its place at the top of the list.]],
	icon = "whiteout",
	mp = 55,
	power = 180,                -- the most damage it deals
	data = { chance = 9 },      -- the chance in 15 that the sleep lasts each turn
	uses = { statuses = { "sleep" } },
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		asleep = "The %s leaves the monster weakened, and it falls asleep.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
			asleep = "The monster casts %s, and you fall asleep.",
		},
	},
	cast = cast,
}
