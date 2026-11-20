-- app/content/spells/magic_bolt.lua :: Magic Bolt (new in 2.4), the Mage's first spell,
-- known from character creation (classes/mage.lua start_spells) and cast by the Wand
-- (items/wand.lua). Hurt's formula with a small power: 3-4 damage, none to monsters immune
-- to hurt spells.
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- like Hurt: rand(max * 5/6, max)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Magic Bolt",
	description = "Hurls a small bolt of force at the monster, whatever its armor. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Before the words that heal or burn, every apprentice learns to throw a spark of pure will.
It stings more than it wounds, but many a Mage has walked home alive behind one.]],
	mp = 1,
	power = 4,                  -- the most damage it deals
	icon = "magic_bolt",        -- public/images/skills/magic_bolt.png
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
