-- app/content/spells/spark.lua :: a crackle of lightning that costs almost nothing. The
-- damage grows by 1 for every 10 levels of the caster, so the spell is still worth a
-- slot at level 60 when the Mage has long outgrown Magic Bolt.
-- learned: mage 6
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power) + math.floor(s.caster.level / 10)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Spark",
	description = "Throws a crackle of lightning at the monster. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Every Mage has singed a finger on this one. It is cheap, it is loud, and it does little
more than make a monster flinch. The old masters kept it in the course anyway, because a
spark costs less than a cup of water and it still works at the end of a long fight.]],
	mp = 3,
	power = 8,                  -- the most damage it deals, before the caster's level bonus
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
