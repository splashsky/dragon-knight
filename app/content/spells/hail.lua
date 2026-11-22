-- app/content/spells/hail.lua :: a hailstorm over the whole field: an area spell, so every foe and
-- every object takes frost damage (Hurt's formula for each, its own roll). About four fifths of
-- a single blow of its level (Rend is 100 for 40 MP at 51) for a quarter more MP.
-- learned: mage 46
local function cast(s)
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		if t:immune_to("frost") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll((s.power / 6) * 5, s.power)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "frost")) else s:say("hit", s.name, t.name, t:hurt(damage, "frost")) end
		end
	end
end

return {
	name = "Hail",
	description = "A hailstorm over the whole field that hits every monster and every object with frost. Some monsters are immune.",
	icon = "hail",
	area = true,                -- hits every foe and object (s.targets)
	mp = 30,
	power = 55,                 -- the most damage it deals to each
	messages = {
		cast = "You have cast the %s spell, and hail pelts the field.",
		hit = "The %s hits the %s for %d damage.",
		immune = "The %s hits the %s, but it is immune to it.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {                    -- when a monster casts it
			cast = "The monster casts %s, and hail pelts the field.",
			hit = "The %s hits the %s for %d damage.",
			hit_you = "The %s hits you for %d damage.",
			immune = "The %s hits the %s, but it is immune to it.",
			immune_you = "The %s hits you, but you are immune to it.",
		},
	},
	cast = cast,
}
