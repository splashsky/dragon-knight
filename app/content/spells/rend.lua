-- app/content/spells/rend.lua :: the Rend spell (the original game's spell 9).
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Rend",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	lore = [[
Rend is the spell old Mages used to finish a monster for them, and some still teach it that
way. It tears at the target's defences and its flesh alike, leaving it bloodied and unsteady.
Hunters in Endworld say a Rend cast well makes a beast forget where it was going.]],
	mp = 40,
	power = 100,                 -- the most damage it deals
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
