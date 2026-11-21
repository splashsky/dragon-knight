-- app/content/spells/dawnstrike.lua :: a holy strike for the Paladin. It hits harder while
-- the caster is wounded (below half HP): the faith of a man with his back to the wall.
-- learned: paladin 16
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	if s.caster.hp * 2 < s.caster.maxhp then
		damage = damage + s:roll(0, math.floor(s.power / 3))
	end
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Dawnstrike",
	description = "Strikes the monster with holy light, harder while you are below half your Hit Points. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The Paladins of Roma say the sun rises for the one who is still standing. Dawnstrike is
a short, bright blow with a hymn behind it, and it is hardly ever cast by a man who feels
well. The priests of Bris teach it to their knights along with the warning that a wounded
man should not wait for the dawn to come to him.]],
	mp = 8,
	power = 24,                 -- the most damage it deals, plus a third more when hurt
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
