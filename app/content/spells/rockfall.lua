-- app/content/spells/rockfall.lua :: the Mage tears the ground up across the field: an area
-- spell, so the stone hits every foe and every object on it (the fight's target doesn't
-- matter). It costs the caster Hit Points as well as MP (the cost is data, shown in the
-- lore), paid once, and it can't be cast by a caster too weak to pay it. Learned by no class
-- by default.
-- learned: mage 42; warrior 76
local function price(s)
	return math.floor(s.caster.maxhp * s.data.cost / 100)
end
local function cast(s)
	local cost = price(s)
	s.caster:spend("hp", cost)
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		if t:immune_to("earth") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll((s.power / 6) * 5, s.power)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "earth")) else s:say("hit", s.name, t.name, t:hurt(damage, "earth")) end
		end
	end
	s:say("cost", cost)
end

return {
	name = "Rockfall",
	description = "Brings stone down on every monster and every object on the field, at the cost of some of your own Hit Points. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The earth under Midworld is soft, and the Mages of Hambry have made it harder to live
with. Rockfall calls up a slab of the road and drops it on whatever is standing there. The
cost is paid in blood: a Mage who casts it loses a few Hit Points of their own, and
the masters will not teach it to anyone who cannot afford the bruises.]],
	icon = "rockfall",
	area = true,                -- hits every foe and object (s.targets)
	mp = 22,
	power = 100,                -- the most damage it deals
	data = { cost = 10 },       -- percent of the maximum HP the caster pays
	messages = {
		cast = "You have cast the %s spell, and stone comes down across the field.",
		hit = "The %s hits the %s for %d damage.",
		cost = "The spell costs you %d Hit Points.",
		immune = "The %s hits the %s, but it is immune to it.",
		weak = "You are too weak to cast the %s spell. It would cost %d Hit Points.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {                    -- when a monster casts it
			cast = "The monster casts %s, and stone comes down across the field.",
			hit = "The %s hits the %s for %d damage.",
			hit_you = "The %s hits you for %d damage.",
			immune = "The %s hits the %s, but it is immune to it.",
			immune_you = "The %s hits you, but you are immune to it.",
			cost = "The monster pays %d Hit Points for it.",
		},
	},
	-- refused (costs nothing) if the caster would be left with no Hit Points
	can_cast = function(s)
		if s.caster.hp <= price(s) then return s:refuse("weak", s.name, price(s)) end
	end,
	cast = cast,
}
