-- app/content/spells/sap_mind.lua :: a force bolt that pulls some of the monster's
-- magic back into the caster: a quarter of the damage returns as MP. Learned by no class by
-- default.
-- learned: mage 29
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
	local back = s.caster:heal("mp", math.floor(damage / 4))
	if back > 0 then s:say("drain", back) end
end

return {
	name = "Sap Mind",
	description = "Hurts the monster with a bolt of force and restores some of your Magic Points. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Some of the old texts call this the thief's spell, and the Mages of Narcissa do not
argue. The bolt goes in as force, and on the way out it takes a little of whatever
the monster was using to keep itself going. Nobody has ever found a way to make it
return the favour, so the Mage who casts it is usually the one who comes out ahead.]],
	mp = 16,
	power = 32,                 -- the most damage it deals; a quarter of it comes back as MP
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		drain = "You recover %d Magic Points.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			drain = "The monster recovers %d Magic Points.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
