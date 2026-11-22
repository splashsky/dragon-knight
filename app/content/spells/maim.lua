-- app/content/spells/maim.lua :: the Maim spell (the original game's spell 8).
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Maim",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	lore = [[
Maim is the spell for when a monster has had enough and is too stubborn to say so. It hits
hard enough to cripple a limb, if the monster has limbs. Mercenaries in Kalle use it as a
sort of shout, and their enemies seldom argue.]],
	icon = "maim",
	mp = 25,
	power = 70,                 -- the most damage it deals
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
