-- app/content/spells/cleave.lua :: the Cleave spell (a blow that trusts the arm, not the book).
-- learned: warrior 6
-- The damage is a share of the caster's strength (up to power), rolled between five sixths of
-- that and the full amount. Armor is ignored, as with the other damage spells.
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local top = math.min(s.power, math.floor(s.caster.strength * s.data.pct / 100))
	local damage = s:roll(math.floor(top * 5 / 6), top)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Cleave",
	description = "Hurts the monster by a share of your strength, whatever its armor. Some monsters are immune.",
	lore = [[
Taught in the training yards at Midworld with a wooden sword and a bucket of sand, so
the sergeants could see where the blow landed. The trick is to swing from the hips and
let the weight of the blade do the work, which is most of what strength is good for. A
Warrior who has done it a thousand times can cut a goblin in half and still be out of
breath for the next one.]],
	mp = 4,
	power = 24,                 -- the most damage it deals
	data = { pct = 100 },       -- percent of your strength it deals before that limit
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
