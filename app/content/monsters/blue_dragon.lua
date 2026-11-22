-- app/content/monsters/blue_dragon.lua :: the Blue Dragon (the original game's monster 116).

local function breath_due(m)
	local n = 4
	if m:has_field("snow") or m:has_field("blizzard") then n = 3 end   -- the cold feeds it
	if m:has_field("heat") or m:has_field("sun") then n = 5 end        -- the warmth slows it
	return m.turn % n == 0
end

return {
	name = "Blue Dragon",
	lore = [[
The blue dragon lives high in the cold peaks above Kalle, where the snow lies on the road
for half the year. It is patient, and it hunts the mountain passes like a judge hunts
debtors. Its breath freezes armour to the skin, so bring a warm cloak and a spare set of
gloves, and do not expect the dragon to be impressed by either.]],
	icon = "blue_dragon",
	level = 39,
	maxhp = 180, maxdam = 160, armor = 130,
	maxexp = 605, maxgold = 202,
	resist = { frost = 75, fire = -50 },
	ward = { sleep = 50 },
	maxmp = 141,
	spells = {
		-- gathers a frost breath every 4th turn (3rd in snow, 5th in heat or sun), then it lands and numbs your arms
		{ spell = "frost_breath", weight = 30, when = breath_due },
	},
	speech = {
		start = { "Cold climbs a long way to reach you, little knight.", "Climb back down. Or stay.", chance = 60 },
		turn = { "Feel the frost in your bones.", "Slow, are you?", chance = 15 },
		winning = { "The pass is closed to you.", chance = 35 },
		losing = { "You break the ice I have kept for ages!", chance = 40 },
		hurt = { "A chill, nothing more.", chance = 20 },
		death = { "The snow will cover me... gently...", chance = 75 },
		victory = { "The pass is quiet again.", chance = 65 },
	},
}
