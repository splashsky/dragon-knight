-- app/content/spells/poison.lua :: poisons the monster for a few turns (new in 2.2: a
-- status, app/content/statuses/poison.lua). Learned by no class by default.
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	s.target:afflict("poison", { turns = s.power, min = s.data.min, max = s.data.max })
	s:say("cast", s.name, s.power)
end

return {
	name = "Poison",
	description = "Poisons the monster: it loses a few hit points every turn. Some monsters are immune.",
	lore = [[
Poison is an old trick brewed in the back rooms of Hambry, where the herbalists keep the
bottles the town guard would rather not inventory. The spell sets a foul sickness in the
monster, which costs it a little life on every turn it lasts. Some creatures have no blood to
spoil, and they shrug it off.]],
	mp = 6,
	power = 3,                  -- how many turns the poison lasts
	data = { min = 2, max = 6 },
	uses = { statuses = { "poison" } },
	messages = {
		cast = "You have cast the %s spell. The monster is poisoned for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			cast = "The monster casts %s. You are poisoned for %d turns.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
