-- app/content/spells/pain.lua :: the Pain spell (the original game's spell 7).
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Pain",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	lore = [[
Pain is the step up from Hurt for Mages with a few coins and a bigger grudge. The jolt is
nastier and the target feels it for longer, though the spell does not make it any smarter.
Many a Paladin learns it to keep a sword arm free for the other work.]],
	icon = "pain",
	mp = 12,
	power = 35,                 -- the most damage it deals
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
