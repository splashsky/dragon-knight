-- app/content/spells/blood_strike.lua :: the Blood Strike spell (the Warrior pays in his own blood).
-- learned: warrior 20
-- The caster loses a share of maximum HP before the blow lands, so it is refused when that
-- loss would leave him dead or at zero. Damage is a share of the caster's attack (up to power).
local function price(s)
	return math.floor(s.caster.maxhp * s.data.cost / 100)
end

return {
	name = "Blood Strike",
	description = "Costs you Hit Points to hurt the monster hard, whatever its armor. Some monsters are immune.",
	lore = [[
Old hands in Roma swear the blood is the point, not the blade: a man who has bled a
little already does not flinch at the rest. It is a bad trade for anyone with a healer
out of reach, and a Warrior who casts it with low HP is asking the undertaker to measure
him. Used once at the right moment, it ends fights that would otherwise go on for three
more rounds.]],
	mp = 10,
	power = 60,                 -- the most damage it deals
	data = { pct = 100, cost = 15 },   -- percent of your attack it deals before that limit;       -- percent of your maximum HP it takes from you
	messages = {
		hit = "You have cast the %s spell for %d damage, and lose %d Hit Points.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		too_weak = "You are too weak from your wounds to cast the %s spell.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s at you for %d damage, and bleeds %d Hit Points.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	-- refused (costs nothing) against an immune monster, or when the cost would finish you
	can_cast = function(s)
		if s.target.immune ~= 0 then return s:refuse("immune", s.name) end
		if s.caster.hp <= price(s) then return s:refuse("too_weak", s.name) end
	end,
	cast = function(s)
		local cost = price(s)
		local top = math.min(s.power, math.floor(s.caster.attack * s.data.pct / 100))
		local damage = s:roll(math.floor(top * 5 / 6), top)
		s.caster:hurt(cost)
		s.target:hurt(damage)
		s:say("hit", s.name, damage, cost)
	end,
}
