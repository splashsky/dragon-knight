-- app/content/spells/call_wolf.lua :: summons a wolf to fight alongside the caster for a
-- few rounds (app/content/summons/wolf.lua). Refused when no more allies may join
-- (s.summon_room: the "Allies" setting, default 1). Learned by no class by default.
local function can_cast(s)
	if s.summon_room < 1 then return s:refuse("no_room") end
end

local function cast(s)
	s:summon("wolf", { ticks = s.power })
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Call Wolf",
	description = "A wolf fights alongside you for a few rounds; monsters may attack it instead of you.",
	lore = [[
Hunters in the hills near Kalle claim a wolf will follow anyone who calls it properly, and
this spell is the proper way. The wolf is no pet: it stays a few rounds, bites what it can
reach, and takes a blow meant for its master when a monster is in the mood.]],
	icon = "call_wolf",
	mp = 10,
	power = 5,                  -- rounds the wolf stays
	target = "self",
	uses = { summons = { "wolf" } },
	messages = {
		cast = "You have cast the %s spell. A wolf joins the fight for %d seconds.",
		no_room = "You can't call another ally now. Please go back and try again.",
	},
	can_cast = can_cast,
	cast = cast,
}
