-- app/content/spells/poison.lua :: poisons the monster for a while (new in 2.2: a
-- status, app/content/statuses/poison.lua). Learned by no class by default.
local function cast(s)
	if s.target:immune_to("poison") then return s:say("immune", s.name) end
	if not s.target:afflict("poison", { ticks = s.power, min = s.data.min, max = s.data.max }) then
		return s:say(s.target:ward("poison") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Poison",
	description = "Poisons the monster: it loses a few hit points every 10 seconds. Some monsters are immune.",
	lore = [[
Poison is an old trick brewed in the back rooms of Hambry, where the herbalists keep the
bottles the town guard would rather not inventory. The spell sets a foul sickness in the
monster, which costs it a little life on every turn it lasts. Some creatures have no blood to
spoil, and they shrug it off.]],
	icon = "poison",
	mp = 6,
	power = 3,                  -- how many ticks the poison lasts
	data = { min = 2, max = 6 },
	uses = { statuses = { "poison" } },
	messages = {
		cast = "You have cast the %s spell. The monster is poisoned for %d seconds.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You are poisoned for %d seconds.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
