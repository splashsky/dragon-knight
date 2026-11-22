-- app/content/spells/water_jet.lua :: a jet of water for a share of the caster's own attack
-- (armor ignored): the drakefin's, the nymph's and the aqua things'. Learned by no class by
-- default: monsters cast it.
local function cast(s)
	if s.target:immune_to("water") then return s:say("immune", s.name) end
	local attack = s.caster.attack
	local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
	s:say("hit", s.name, s.target:hurt(damage, "water"))
end

return {
	name = "Water Jet",
	description = "Hurls a jet of water for about two fifths of the caster's attack, whatever the armor. Some monsters are immune.",
	lore = [[
A jet of water hits like a fist and does about two fifths of the caster's attack, armour
or no armour. The drakefins of the Hambry marsh fire it, and so do the nymphs by the
ponds and the aqua things of the flooded mines past Gilead. There is no wind-up. The
splash is the warning, and by then the jet has already landed. Fishers say the nymphs
only fire it at men who have been singing.]],
	icon = "water_jet",
	mp = 8,
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
