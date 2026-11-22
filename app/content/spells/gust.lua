-- app/content/spells/gust.lua :: a gust of wind at the monster: Hurt's formula with wind damage,
-- the Mage's way to reach monsters that are weak to wind.
-- learned: mage 22
local function cast(s)
	if s.target:immune_to("wind") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- as Hurt: rand(power * 5/6, power)
	s:say("hit", s.name, s.target:hurt(damage, "wind"))
end

return {
	name = "Gust",
	description = "Throws a gust of wind at the monster. Some monsters are immune.",
	icon = "gust",
	mp = 12,
	power = 30,                 -- the most damage it deals
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
