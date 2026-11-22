-- app/content/spells/lightning_lance.lua :: a long bolt of lightning. The caster must
-- recharge on the next turn, as after Hyper Beam, unless the monster went down under the
-- blow: a kill leaves the Mage free to act. Learned by no class by default.
-- learned: mage 62
local function cast(s)
	if s.target.immune ~= 0 then
		s:say("immune", s.name)
		return s:recharge(1)
	end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
	if s.target.hp > 0 then
		s:say("recharge")
		s:recharge(1)
	end
end

return {
	name = "Lightning Lance",
	description = "A long bolt of lightning. You must recharge on the next turn unless it slays the monster. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Lightning goes where it is pointed, and the trick with a lance is that it leaves the
hand for good. The Mages of Endworld fire it down the long road at anything that walks
up it, then sit on the stones for a turn while their heads stop ringing. A monster that
falls to the blast costs them nothing more, so the wise ones aim it carefully.]],
	icon = "lightning_lance",
	mp = 35,
	power = 150,                -- the most damage it deals
	uses = { statuses = { "recharging" } },
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		recharge = "You must recharge next turn.",
		immune = "You have cast the %s spell, but the monster is immune to it. You must recharge next turn.",
		enemy = {
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
