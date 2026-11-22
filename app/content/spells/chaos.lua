-- app/content/spells/chaos.lua :: the Chaos spell (the original game's spell 10).
local function cast(s)
	if s.target:immune_to("arcane") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s:say("hit", s.name, s.target:hurt(damage, "arcane"))
end

return {
	name = "Chaos",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	lore = [[
Scholars argue over whether Chaos was written by a Mage or a madman, and the spell does not
settle the question. It tears at a monster's form with no regard for its armor, and in the
deep towns of Gilead it has ended more than one lord's bodyguard. Casters use it only when
nothing gentler will do.]],
	icon = "chaos",
	mp = 50,
	power = 130,                 -- the most damage it deals
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
