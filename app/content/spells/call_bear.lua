-- app/content/spells/call_bear.lua :: summons a bear to fight alongside the caster for a few
-- rounds (app/content/summons/bear.lua). Refused when no more allies may join
-- (s.summon_room). Learned by no class by default.
-- learned: warrior 24; paladin 27
local function can_cast(s)
	if s.summon_room < 1 then return s:refuse("no_room") end
end

local function cast(s)
	s:summon("bear", { ticks = s.power })
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Call Bear",
	description = "A bear fights alongside you for a few rounds; monsters may attack it instead of you.",
	lore = [[
Bears come down from the hills above Roma in the autumn, looking for honey and not for
trouble. A few Warriors and Paladins have found a way to borrow one for a fight, by promising
it something it wants more than the fight. The bear is not grateful, but it hits very hard,
and it stays only as long as the spell does.]],
	icon = "call_bear",
	mp = 12,
	power = 4,                  -- rounds the bear stays
	target = "self",
	uses = { summons = { "bear" } },
	messages = {
		cast = "You have cast the %s spell. A bear joins the fight for %d seconds.",
		no_room = "You can't call another ally now. Please go back and try again.",
	},
	can_cast = can_cast,
	cast = cast,
}
