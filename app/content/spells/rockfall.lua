-- app/content/spells/rockfall.lua :: the Mage tears the ground up under the monster. It costs
-- the caster Hit Points as well as MP (the cost is data, shown in the lore), and it can't
-- be cast by a caster too weak to pay it. Learned by no class by default.
-- learned: mage 42; warrior 76
local function price(s)
	return math.floor(s.caster.maxhp * s.data.cost / 100)
end
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	local cost = price(s)
	s.caster:spend("hp", cost)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
	s:say("cost", cost)
end

return {
	name = "Rockfall",
	description = "Brings stone down on the monster, at the cost of some of your own Hit Points. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The earth under Midworld is soft, and the Mages of Hambry have made it harder to live
with. Rockfall calls up a slab of the road and drops it on whatever is standing there. The
cost is paid in blood: a Mage who casts it loses a few Hit Points of their own, and
the masters will not teach it to anyone who cannot afford the bruises.]],
	mp = 22,
	power = 100,                -- the most damage it deals
	data = { cost = 10 },       -- percent of the maximum HP the caster pays
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		cost = "The spell costs you %d Hit Points.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		weak = "You are too weak to cast the %s spell. It would cost %d Hit Points.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
			cost = "The monster pays %d Hit Points for it.",
		},
	},
	-- refused (costs nothing) if the caster would be left with no Hit Points
	can_cast = function(s)
		if s.caster.hp <= price(s) then return s:refuse("weak", s.name, price(s)) end
	end,
	cast = cast,
}
