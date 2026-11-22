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
	lore = [[
Mages learn Gust at twenty-two, when a student is trusted with a spell that makes a
noise. A gust has no smell and no colour, and most monsters see it only when it is
already in their face. It hits the ones that are weak to wind harder than the rest, and
it does nothing to the ones that are not. The masters in Midworld say a Mage who can
throw wind is never short of a way to move the furniture.]],
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
