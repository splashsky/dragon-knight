-- app/content/spells/frostbite.lua :: a frost bolt that sometimes numbs the monster into a
-- sleep. One hit in three the cold takes hold and the monster sleeps (the sleep status,
-- as Sleep does). Learned by no class by default.
-- learned: mage 16
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
	if s:roll(1, 3) == 1 then
		s.target:sleep(s.data.chance)
		s:say("asleep", s.name)
	end
end

return {
	name = "Frostbite",
	description = "Hurts the monster with frost, and may numb it to sleep. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Ice on a Mage's staff is a bad sign, but ice in a monster's joints is the Mage's friend.
Frostbite stings the skin and stiffens the limbs, and one time in three the cold goes
deep enough that the beast sits down and forgets the fight. Miners in Kalle swear by it
when a cave bear wanders in from the back passages.]],
	icon = "frostbite",
	mp = 9,
	power = 22,                 -- the most damage it deals
	data = { chance = 6 },      -- the chance in 15 that the sleep lasts each turn
	uses = { statuses = { "sleep" } },
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		asleep = "The %s numbs the monster, and it falls asleep.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
			asleep = "The monster casts %s, and you fall asleep.",
		},
	},
	cast = cast,
}
