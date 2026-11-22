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
