-- app/content/interactables/campfire.lua :: a ring of blackened stones and a few red coals (the
-- Copper Downs' goblin camps; docs/APP.md "Interactables and targeting"). Now and then a spark
-- flies and sets another object on the field alight: a barrel beside it goes off by itself. Water
-- (a hit, or being soaked) puts it out.
local DAMP = { "rain", "downpour", "thunderstorm", "snow", "blizzard", "shallows" }

return {
	name = "Campfire",
	description = "A few red coals in a ring of stones. About every 30 seconds a spark flies and sets another object on the "
		.. "field alight. Water puts it out.",
	lore = [[
Every goblin camp on the Copper Downs has one, and so does most of the drovers' yards out
of Roma. Goblins say a spark that lands on your boot is the fire looking for something
bigger, and that a barrel beside a camp is asking for trouble. The washerwomen of Roma
keep a bucket by the door for the same reason, and they count themselves lucky when it
hisses.]],
	icon = "campfire",
	hp = 8,
	resist = { water = -100, fire = 100 },
	spawn = {
		{ biomes = { "downs" }, fields = { "night" }, unless = DAMP, chance = 18 },
		{ biomes = { "downs" }, unless = DAMP, chance = 10 },
	},
	data = { chance = 3, ticks = 2, amount = 3 },   -- a spark 1 tick in `chance`: burning for ticks of amount
	messages = {
		placed = "A campfire smoulders in a ring of stones, a kettle on a tripod.",
		crackle = "The campfire spits a few sparks and crackles.",
		spark = "A spark from the campfire lands on the %s.",
		fizzle = "A spark from the campfire fizzles out.",
		out = "The fire goes out in a hiss.",
		scattered = "The campfire is scattered.",
	},
	uses = { statuses = { "burning" } },
	on_place = function(o) o:say("placed") end,
	on_damage = function(o, _, element)
		if element == "water" then o.self:destroy("water") end
	end,
	on_status = function(o, key)
		if key == "soaked" then o.self:destroy("water") end
	end,
	on_tick = function(o)
		if o:roll(1, o.data.chance) ~= 1 then return end
		if #o.objects == 0 then return o:say("crackle") end
		local other = o.objects[o:roll(1, #o.objects)]
		if other:afflict("burning", { ticks = o.data.ticks, amount = o.data.amount }) then
			o:say("spark", other.name)
		else
			o:say("fizzle")
		end
	end,
	on_destroyed = function(o, element)
		o:say(element == "water" and "out" or "scattered")
	end,
}
