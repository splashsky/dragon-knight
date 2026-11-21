-- app/content/spells/call_golem.lua :: raises a stone golem to stand beside the caster for a
-- few rounds (app/content/summons/golem.lua). Refused when no more allies may join
-- (s.summon_room). Learned by no class by default.
-- learned: mage 94; warrior 64; paladin 68
local function can_cast(s)
	if s.summon_room < 1 then return s:refuse("no_room") end
end

local function cast(s)
	s:summon("golem", { turns = s.power })
	s:say("cast", s.name, s.power)
end

return {
	name = "Raise Golem",
	description = "A stone golem stands beside you for a few rounds; monsters may attack it instead of you.",
	lore = [[
The golem is built from river stone and a few words the builder would rather not repeat in
company. It takes a long time to wake and it is slow to turn, but once it has started there
is little a monster can do about it. Paladins use it to hold a line while the rest of the
party recovers, and then they thank it, because a golem that is not thanked seems to take
longer to rise the next time.]],
	mp = 40,
	power = 4,                  -- rounds the golem stays
	target = "self",
	uses = { summons = { "golem" } },
	messages = {
		cast = "You have cast the %s spell. A golem joins the fight for %d rounds.",
		no_room = "You can't call another ally now. Please go back and try again.",
	},
	can_cast = can_cast,
	cast = cast,
}
