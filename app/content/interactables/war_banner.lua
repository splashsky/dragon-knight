-- app/content/interactables/war_banner.lua :: a torn standard on a broken lance (the Storm
-- Barrens' battlefields; a knight's war_standard places one; docs/APP.md "Interactables and
-- targeting"). Everyone on the side it flies over is rallied (the status rallied: more damage
-- dealt) for as long as it stands. A gale tears it down; fire takes it at once (fire -100).
local function rally(o)
	for _, h in ipairs(o.combatants) do
		if (h.side == "enemy") == (o.self.over == "enemy") then h:afflict("rallied", { ticks = o.data.ticks, pct = o.data.pct }) end
	end
end

return {
	name = "War Banner",
	description = "A torn standard flying over one side of the field: everyone on that side deals 25% more damage while it "
		.. "stands. A gale tears it down, fire burns it at once.",
	lore = [[
The war standards of Gilead go up where the men can see them, and the men fight harder for
the sight of one. The Storm Barrens tear more banners down than any enemy does, and the
ballads say a standard that falls takes the courage with it. Every soldier who has served
on the Barrens has seen one come down in a squall, and nobody talks about what happened
next.]],
	icon = "war_banner",
	hp = 10,
	hp_per_level = 1,
	resist = { fire = -100 },
	spawn = {
		{ biomes = { "barrens" }, unless = { "thunderstorm", "blizzard" }, chance = 8 },
	},
	data = { ticks = 2, pct = 25 },   -- the rally it puts on again every tick: its time and percent
	messages = {
		placed = "A torn war banner snaps in the wind over %s.",
		torn = "The wind tears the banner down.",
		fallen = "The banner falls.",
	},
	uses = { statuses = { "rallied" } },
	on_place = function(o)
		o:say("placed", o.self.over == "player" and "you" or "the monster")
		rally(o)
	end,
	on_tick = function(o)
		if o.wind >= 3 then
			o:say("torn")
			return o.self:destroy()
		end
		rally(o)
	end,
	on_destroyed = function(o) o:say("fallen") end,
}
