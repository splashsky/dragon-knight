-- app/content/spells/reaver.lua :: the Reaver spell (a strong blow that feeds the one who swings it).
-- learned: warrior 28; paladin 31
-- Damage is a share of the caster's strength (up to power); the caster heals half of what was dealt.
local function cast(s)
	local top = math.min(s.power, math.floor(s.caster.strength * s.data.pct / 100))
	local damage = s:roll(math.floor(top * 5 / 6), top)
	local dealt = s.target:hurt(damage)
	local healed = s.caster:heal("hp", math.floor(dealt / 2))
	s:say("hit", s.name, dealt, healed)
end

return {
	name = "Reaver",
	description = "Hurts the monster by a share of your strength and heals you for half of it.",
	lore = [[
The reavers of the northern road were never gentle men, and their trick was simple: the
blood on the blade went back into the body that spilt it. Paladins who ride with the
caravans pick it up for the same reason, though they say a prayer while they do it. The
heal is small next to a proper healing spell, but it arrives in the middle of a fight,
where a Herb cannot reach you.]],
	icon = "reaver",
	mp = 12,
	power = 50,                 -- the most damage it deals
	data = { pct = 100 },       -- percent of your strength it deals before that limit
	messages = {
		hit = "You have cast the %s spell for %d damage, and gained %d Hit Points.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage, and heals %d Hit Points.",
		},
	},
	cast = cast,
}
