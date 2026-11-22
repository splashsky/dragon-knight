-- app/content/monsters/goblin.lua :: the Goblin (the original game's monster 28).
local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
		or m:has_field("blizzard") or m:has_field("shallows")
end

local function barrel(m)
	for _, o in ipairs(m.objects) do
		if o.key == "explosive_barrel" then return o end
	end
end

-- rolls a keg onto the field on its second turn, never in damp air
local function rolls_out(m)
	return m.turn == 2 and not barrel(m) and not wet(m)
end

-- lights the keg from its third turn on, when you could take twice its blast (40% of its attack); in a camp the fire does it
local function lights(m)
	local b = barrel(m)
	return m.turn >= 3 and b and not b:has_status("fuse") and not wet(m)
		and m.target.hp > m.attack * 8 // 10 and not m:has_object("campfire")
end

return {
	name = "Goblin",
	lore = [[
Small, green and loud, goblins live in the hills along the road out of Roma and steal anything
they can carry. They raid caravans and run before the guards arrive. A goblin will bargain, lie,
and bargain again, and seldom keeps to any of it.]],
	icon = "goblin",
	level = 10,
	maxhp = 36, maxdam = 30, armor = 15,
	maxexp = 54, maxgold = 18,
	maxmp = 36,
	items = {
		-- rolls a keg of blasting powder onto the field on its second turn
		{ item = "explosive_barrel", weight = 5, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from its third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	speech = {
		start = { "Shiny! Mine now!", "Hey you! Give it here!", chance = 50 },
		turn = {
			"Hee hee, mine!", "Put that down, it's ours.",
			{ text = "Goblin got a present for you! Hee hee!", weight = 4, when = rolls_out },
			{ text = "Boom time! Boom time!", weight = 4, when = lights },
			chance = 25,
		},
		winning = { "Got you, {player}! Got you!", chance = 30 },
		losing = { "Not fair! Goblin ran away!", "Bah! Next time!", chance = 35 },
		hurt = { "Ow! Ow! That hurts!", chance = 30 },
		death = { "Mama... mama...", chance = 60 },
		victory = { "Ha! Shiny for goblin!", chance = 60 },
	},
}
