-- app/content/spells/knock_over.lua :: a heavy swing for a monster that wants an object down (a
-- troll at a standing stone, a bear at a hive: the loadout's `aim`): a share of the caster's
-- own attack, armor ignored, twice that against an object. Against a creature it is a weaker
-- Attack, so a loadout only picks it with an `aim`. Learned by no class: monsters cast it.
local function cast(s)
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	if s.target.side == "object" then
		return s:say("hit_object", s.name, s.target.name, s.target:hurt(damage * s.data.objects))
	end
	if s.target.is_player then return s:say("hit_you", s.name, s.target:hurt(damage)) end
	s:say("hit", s.name, s.target.name, s.target:hurt(damage))
end

return {
	name = "Knock Over",
	description = "A heavy swing for about three quarters of the caster's attack, whatever the armor, and twice that against an object.",
	lore = [[
No Mage or Warrior learns this swing; monsters use it on whatever stands in their way. The
Troll, the Titan, the Giant and the Ogre smash a standing stone that leans over you, or fell
a dead tree onto you, once a round has gone by and only when the fall would not finish you.
The Bog Witch pops a gas pocket with her broom, and the bears rake down the hive over your
head. Most of them say so first, and the card reads "over you".]],
	icon = "knock_over",
	mp = 2,
	data = { min = 66, max = 83, objects = 2 },   -- percent of the caster's attack; times more against an object
	messages = {
		hit = "You have cast the %s spell on the %s for %d damage.",
		hit_object = "You have cast the %s spell, and knock the %s over for %d damage.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		enemy = {                    -- when a monster casts it
			hit = "The monster uses %s on the %s for %d damage.",
			hit_you = "The monster uses %s on you for %d damage.",
			hit_object = "The monster uses %s, and knocks the %s over for %d damage.",
		},
	},
	cast = cast,
}
