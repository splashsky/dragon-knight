-- app/content/spells/starfall.lua :: the late-game heavy hitter. The Mage gathers the
-- night for a turn, then a burning star comes down on the monster. Learned by no class by
-- default.
-- learned: mage 76
local function release(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Starfall",
	description = "Gathers the night sky for a turn, then drops a burning star on the monster. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Starfall is the spell the Mages of Hambry save their coin for, because it cannot be
bought in a shop. It needs a clear sky, a steady hand, and a full turn in which to
watch the monster and do nothing else. When the star comes it is about the size of a
cart, and the road it lands on is never the same afterwards.]],
	mp = 60,
	power = 260,                -- the most damage it deals
	uses = { statuses = { "charging" } },
	messages = {
		charge = "You have cast the %s spell, and gather the night sky.",
		hit = "The %s falls for %d damage.",
		immune = "The %s falls, but the monster is immune to it.",
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
