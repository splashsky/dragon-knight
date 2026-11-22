-- app/content/spells/deluge.lua :: a wall of water: an area spell that hits every foe of the
-- caster and every object on the field for a share of the caster's own attack (armor
-- ignored: it douses every fuse) and brings a downpour over the battlefield (the downpour
-- field, in place of the sky's), where lightning is strong and no fire can catch. Learned by
-- no class by default: monsters cast it.
local function cast(s)
	local attack = s.caster.attack
	for _, t in ipairs(s.targets) do
		if t:immune_to("water") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll(attack * s.data.min // 100, attack * s.data.max // 100)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "water")) else s:say("hit", s.name, t.name, t:hurt(damage, "water")) end
		end
	end
	if s:field("downpour", { ticks = s.power }) then s:say("downpour", s:seconds(s.power)) end
end

return {
	name = "Deluge",
	description = "Floods every monster and every object on the field for about a third of the caster's attack, whatever the armor, and brings a downpour over the battlefield for 40 seconds. Some monsters are immune.",
	lore = [[
A wall of water comes off the lake all at once, and the Leviathan is said to throw it. It
strikes for a third of the caster's attack, straight through armour, and then the sky
opens over the field for a while. There is no wind-up to watch for. Fishers near Hambry
say the first they know of it is the wet.
Nobody has ever seen a Deluge cast by a man.]],
	icon = "deluge",
	area = true,                -- hits every foe and object (s.targets)
	mp = 30,
	power = 4,                  -- how many ticks the downpour lasts
	data = { min = 33, max = 40 },   -- percent of the caster's attack
	uses = { fields = { "downpour" } },
	messages = {
		hit = "Your %s floods the %s for %d damage.",
		downpour = "A downpour hammers the field for %d seconds.",
		immune = "Your %s floods the %s, but it is immune to it.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {
			hit = "The monster's %s floods the %s for %d damage.",
			hit_you = "The monster casts %s on you for %d damage.",
			downpour = "A downpour hammers the field for %d seconds.",
			immune = "The monster's %s floods the %s, but it is immune to it.",
			immune_you = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
