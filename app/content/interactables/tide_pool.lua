-- app/content/interactables/tide_pool.lua :: a rock pool of brine, crabs and weed (the Salt Shoals
-- and any shallows; docs/APP.md "Interactables and targeting"). Any hit that breaks it splashes
-- the whole field: everyone, objects too, is soaked (the status soaked), which puts out fires
-- and fuses and keeps them from catching, and makes lightning and frost bite deeper.
local STAY_OUT = { "snow", "blizzard" }

return {
	name = "Tide Pool",
	description = "A rock pool of brine. Break it and everyone on the field is soaked for 30 seconds: fires and fuses go "
		.. "out, fire does 25% less, lightning 30% more and frost 10% more.",
	icon = "tide_pool",
	hp = 8,
	spawn = {
		{ biomes = { "shoals" }, unless = STAY_OUT, chance = 12 },
		{ fields = { "shallows" }, unless = STAY_OUT, chance = 6 },
	},
	data = { ticks = 3 },   -- how long the soaking lasts
	messages = {
		placed = "A rock pool of brine gurgles among the weed, crabs scuttling in it.",
		splash = "The pool splashes over the field, cold and salt!",
	},
	uses = { statuses = { "soaked" } },
	on_place = function(o) o:say("placed") end,
	on_destroyed = function(o)
		o:say("splash")
		for _, h in ipairs(o.combatants) do h:afflict("soaked", { ticks = o.data.ticks }) end
		for _, h in ipairs(o.objects) do h:afflict("soaked", { ticks = o.data.ticks }) end
	end,
}
