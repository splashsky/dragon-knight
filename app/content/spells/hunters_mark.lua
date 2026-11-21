-- app/content/spells/hunters_mark.lua :: the Hunter's Mark spell: marks the monster so that it takes
-- more damage from weapon attacks for a few turns (app/content/statuses/marked.lua; spells
-- and allies do not pass the damage hooks, so only the blows of a weapon count). Learned by no class by default.
-- learned: warrior 40
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	s.target:afflict("marked", { turns = s.power, pct = s.data.pct })
	s:say("cast", s.name, s.power)
end

return {
	name = "Hunter's Mark",
	description = "Marks the monster: it takes more damage from your weapon for a few turns. Some monsters are immune.",
	lore = [[
Hunters in the hills above Kalle chalk a sign on the track where a wounded animal ran, so the
next party knows what it is following. The spell draws the same sign in light on the
monster's hide. For a few turns every swing of a weapon lands harder on the marked creature,
which is why warriors cast it just before they swing.]],
	mp = 12,
	power = 4,                  -- how many turns the mark lasts
	data = { pct = 50 },        -- percent more damage taken from weapon attacks
	uses = { statuses = { "marked" } },
	messages = {
		cast = "You have cast the %s spell. The monster is marked for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
	},
	cast = cast,
}
