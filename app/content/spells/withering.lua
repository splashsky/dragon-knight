-- app/content/spells/withering.lua :: the Withering spell: drains the monster every 10 seconds, and
-- the caster gains back what it loses (app/content/statuses/withering.lua). Learned by no
-- class by default.
-- learned: mage 54; paladin 53
local function cast(s)
	if s.target:immune_to("shadow") then return s:say("immune", s.name) end
	if not s.target:afflict("withering", { ticks = s.power, min = s.data.min, max = s.data.max }) then
		return s:say(s.target:ward("withering") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Withering",
	description = "Drains the monster's hit points every 10 seconds for a while; you gain what it loses. Some monsters are immune.",
	lore = [[
Old Gilead has a saying that the Mage who lives on other people's blood is still a Mage, but
a thin one. Withering is the spell that makes the saying true. It pulls strength out of the
target a little each turn and passes it to the caster, so a long fight can be turned around
by a caster who is patient enough to wait for it. Most Mages who learn it stop being thin.]],
	icon = "withering",
	mp = 34,
	power = 4,                  -- how many ticks the drain lasts
	data = { min = 14, max = 24 },   -- hit points drained per tick
	uses = { statuses = { "withering" } },
	messages = {
		cast = "You have cast the %s spell. The monster withers for %d seconds.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You wither for %d seconds.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
