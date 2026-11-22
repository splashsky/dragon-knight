-- app/content/statuses/rallied.lua :: a war banner's rally: more damage dealt, in percent, for
-- as long as the banner stands (it puts it on again every tick; two ticks after it falls the
-- rally is over). A status of its own, so the banner never replaces a Craze or a Rage.
return {
	name = "Rallied",
	description = "Deals 25% more damage while the war banner stands.",
	lore = [[
The shout that goes down the line when a standard goes up, and every blade on that side
bites harder for it. Sergeants call it the cheapest thing on a battlefield and the first
thing to go. It lingers for a moment after the banner falls, long enough for the men to
notice that the cheering has stopped.]],
	icon = "rallied",
	kind = "helpful",
	ticks = 2,
	data = { pct = 25 },
	modify_damage_dealt = function(t, damage)
		return damage + math.ceil(damage * (t.data.pct / 100))
	end,
}
