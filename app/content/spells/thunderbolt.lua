-- app/content/spells/thunderbolt.lua :: a bolt of lightning for a share of the caster's own
-- attack (armor ignored): the storm things' and the liche master's. Learned by no class by
-- default: monsters cast it.
local function cast(s)
	if s.target:immune_to("lightning") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "lightning"))
end

return {
	name = "Thunderbolt",
	description = "Hurls a bolt of lightning for about two fifths of the caster's attack, whatever the armor. Some monsters are immune.",
	lore = [[
A bolt of lightning that comes out of a clear sky with a crack like a tree splitting. It
does about two fifths of the caster's attack, and armour is no help against it. The
storm things of the high ridges throw it, and so does the Liche Master when a lesson
goes badly. There is no wind-up to watch for, only the crack, and by then the bolt has
already landed.]],
	icon = "thunderbolt",
	mp = 14,
	data = { min = 35, max = 42 },   -- percent of the caster's attack
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
