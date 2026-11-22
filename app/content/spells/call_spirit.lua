-- app/content/spells/call_spirit.lua :: summons a spirit to fight alongside the caster for a
-- few rounds (app/content/summons/spirit.lua). Refused when no more allies may join
-- (s.summon_room). Learned by no class by default.
-- learned: mage 35; paladin 41
local function can_cast(s)
	if s.summon_room < 1 then return s:refuse("no_room") end
end

local function cast(s)
	s:summon("spirit", { ticks = s.power })
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Call Spirit",
	description = "A spirit fights alongside you for a few rounds; monsters may attack it instead of you.",
	lore = [[
A spirit is what is left of a person who has not finished their business, or so the priests
of Narcissa say. Mages call one for the length of a fight and send it off afterwards, and
they are careful to say a proper thank you, since a spirit that feels ignored tends to
wander. It is hard to hit and quick on its feet, though it does not hit very hard itself.]],
	icon = "call_spirit",
	mp = 20,
	power = 6,                  -- ticks the spirit stays (the clock's, 10 s each)
	target = "self",
	uses = { summons = { "spirit" } },
	messages = {
		cast = "You have cast the %s spell. A spirit joins the fight for %d seconds.",
		no_room = "You can't call another ally now. Please go back and try again.",
	},
	can_cast = can_cast,
	cast = cast,
}
