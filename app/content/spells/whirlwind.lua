-- app/content/spells/whirlwind.lua :: the Warrior's spin: Cleave's formula (a share of the caster's
-- strength, up to power, armor ignored) for every foe and every object on the field, an area
-- spell. A monster's strength is 0, so it would do nothing; none learns it.
-- learned: warrior 44
local function cast(s)
	local top = math.min(s.power, math.floor(s.caster.strength * s.data.pct / 100))
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		local damage = s:roll(math.floor(top * 5 / 6), top)
		if t.is_player then s:say("hit_you", s.name, t:hurt(damage)) else s:say("hit", s.name, t.name, t:hurt(damage)) end
	end
end

return {
	name = "Whirlwind",
	description = "Spins with your weapon out, hurting every monster and every object on the field by a share of your strength, whatever their armor.",
	lore = [[
Warriors learn the Whirlwind at forty-four, once the sword masters are sure they can keep
their feet while they spin. The blade goes round at arm's length and reaches everything on
the field, monsters and objects alike, armour or no armour. The yard masters say the practice
posts take it as hard as the men do, which is why the yards keep a few of them standing.]],
	icon = "whirlwind",
	area = true,                -- hits every foe and object (s.targets)
	mp = 14,
	power = 55,                 -- the most damage it deals to each
	data = { pct = 75 },        -- percent of your strength it deals before that limit
	messages = {
		cast = "You have cast the %s spell, and spin with your weapon out.",
		hit = "The %s hits the %s for %d damage.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		enemy = {                    -- when a monster casts it
			cast = "The monster casts %s, and spins with its weapon out.",
			hit = "The %s hits the %s for %d damage.",
			hit_you = "The %s hits you for %d damage.",
		},
	},
	cast = cast,
}
