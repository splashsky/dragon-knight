-- app/content/spells/torrent.lua :: a torrent of water at the monster: Hurt's formula with water damage,
-- the Mage's way to reach monsters that are weak to water.
-- learned: mage 24
local function cast(s)
	if s.target:immune_to("water") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- as Hurt: rand(power * 5/6, power)
	s:say("hit", s.name, s.target:hurt(damage, "water"))
end

return {
	name = "Torrent",
	description = "Drenches the monster in a torrent of water. Some monsters are immune.",
	lore = [[
Torrent is a Hurt with water in place of the arcane, and it finds the monsters that fire
spells cannot touch. Mages learn it at twenty-four, from the masters of Midworld, who
warn them never to cast it while standing in a river. The student who ignores the
warning is usually found at the next ford, still dripping and still explaining. The
spell itself works perfectly well.]],
	icon = "torrent",
	mp = 14,
	power = 38,                 -- the most damage it deals
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
