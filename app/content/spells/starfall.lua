-- app/content/spells/starfall.lua :: the late-game heavy hitter. The Mage gathers the
-- night for a turn, then a burning star comes down on the whole field: an area spell, it
-- hits every foe and every object. Learned by no class by default.
-- learned: mage 76
local function release(s)
	for _, t in ipairs(s.targets) do
		if t:immune_to("arcane") then
			if t.is_player then s:say("immune_you", s.name) else s:say("immune", s.name, t.name) end
		else
			local damage = s:roll((s.power / 6) * 5, s.power)
			if t.is_player then s:say("hit_you", s.name, t:hurt(damage, "arcane")) else s:say("hit", s.name, t.name, t:hurt(damage, "arcane")) end
		end
	end
end

return {
	name = "Starfall",
	description = "Gathers the night sky for a turn, then drops a burning star on every monster and every object on the field. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Starfall is the spell the Mages of Hambry save their coin for, because it cannot be
bought in a shop. It needs a clear sky, a steady hand, and a full turn in which to
watch the monster and do nothing else. When the star comes it is about the size of a
cart, and the road it lands on is never the same afterwards.]],
	icon = "starfall",
	area = true,                -- hits every foe and object (s.targets)
	mp = 60,
	power = 260,                -- the most damage it deals
	uses = { statuses = { "charging" } },
	messages = {
		charge = "You have cast the %s spell, and gather the night sky.",
		hit = "The %s falls on the %s for %d damage.",
		immune = "The %s falls on the %s, but it is immune to it.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		hit_you = "The %s hits you for %d damage.",
		immune_you = "The %s hits you, but you are immune to it.",
		enemy = {                    -- when a monster casts it
			charge = "The monster gathers the night sky for its %s.",
			hit = "The %s falls on the %s for %d damage.",
			hit_you = "The %s falls on you for %d damage.",
			immune = "The %s falls on the %s, but it is immune to it.",
			immune_you = "The %s falls on you, but you are immune to it.",
		},
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
