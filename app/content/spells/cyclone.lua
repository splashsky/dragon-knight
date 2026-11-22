-- app/content/spells/cyclone.lua :: a column of wind over the field: an area spell, so every foe and
-- every object takes wind damage (Hurt's formula for each, its own roll). Gust's big sister (12
-- MP for 30 at level 22): about four fifths of Rend's blow (100 for 40 MP at 51) for a quarter
-- more MP.
-- learned: mage 52
local function cast(s)
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		if t:immune_to("wind") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll((s.power / 6) * 5, s.power)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "wind")) else s:say("hit", s.name, t.name, t:hurt(damage, "wind")) end
		end
	end
end

return {
	name = "Cyclone",
	description = "A column of wind over the whole field that hits every monster and every object. Some monsters are immune.",
	icon = "cyclone",
	area = true,                -- hits every foe and object (s.targets)
	mp = 38,
	power = 85,                 -- the most damage it deals to each
	messages = {
		cast = "You have cast the %s spell, and a column of wind tears across the field.",
		hit = "The %s hits the %s for %d damage.",
		immune = "The %s hits the %s, but it is immune to it.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {                    -- when a monster casts it
			cast = "The monster casts %s, and a column of wind tears across the field.",
			hit = "The %s hits the %s for %d damage.",
			hit_you = "The %s hits you for %d damage.",
			immune = "The %s hits the %s, but it is immune to it.",
			immune_you = "The %s hits you, but you are immune to it.",
		},
	},
	cast = cast,
}
