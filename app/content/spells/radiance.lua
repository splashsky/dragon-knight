-- app/content/spells/radiance.lua :: holy light over the whole field: an area spell, so every foe and
-- every object takes holy damage (Hurt's formula for each, its own roll; stronger under
-- consecrated ground like every holy spell). About four fifths of Judgement's blow (140 for 32
-- MP at 64) at the same MP.
-- learned: paladin 58
local function cast(s)
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		if t:immune_to("holy") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll((s.power / 6) * 5, s.power)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "holy")) else s:say("hit", s.name, t.name, t:hurt(damage, "holy")) end
		end
	end
end

return {
	name = "Radiance",
	description = "Holy light over the whole field that hits every monster and every object. Some monsters are immune.",
	icon = "radiance",
	area = true,                -- hits every foe and object (s.targets)
	mp = 32,
	power = 80,                 -- the most damage it deals to each
	messages = {
		cast = "You have cast the %s spell, and holy light floods the field.",
		hit = "The %s hits the %s for %d damage.",
		immune = "The %s hits the %s, but it is immune to it.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {                    -- when a monster casts it
			cast = "The monster casts %s, and holy light floods the field.",
			hit = "The %s hits the %s for %d damage.",
			hit_you = "The %s hits you for %d damage.",
			immune = "The %s hits the %s, but it is immune to it.",
			immune_you = "The %s hits you, but you are immune to it.",
		},
	},
	cast = cast,
}
