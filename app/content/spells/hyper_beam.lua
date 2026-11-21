-- app/content/spells/hyper_beam.lua :: a big hit, then the caster must recharge: it can't
-- act on its next turn (the status recharging; the fight page offers only "Continue").
-- Learned by no class by default.
local function cast(s)
	if s.target.immune ~= 0 then
		s:say("immune", s.name)
	else
		local damage = s:roll((s.power / 6) * 5, s.power)
		s.target:hurt(damage)
		s:say("hit", s.name, damage)
	end
	s:recharge(1)
end

return {
	name = "Hyper Beam",
	description = "A powerful blast, but you must recharge on the next turn. Some monsters are immune.",
	lore = [[
A Mage in Roma once fired three in a row and fell over, which is why the spell now comes with
a warning. The beam hits hard, but the caster's body needs a turn to recover from the strain.
Use it when the monster is already weak and there is no time to waste.]],
	mp = 15,
	power = 60,                 -- the most damage it deals
	uses = { statuses = { "recharging" } },
	messages = {
		hit = "You have cast the %s spell for %d damage. You must recharge next turn.",
		immune = "You have cast the %s spell, but the monster is immune to it. You must recharge next turn.",
		enemy = {
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
