-- app/content/monsters/red_dragon.lua :: the Red Dragon (the original game's monster 121).

local function unraged(m)
	return not m:has_status("uber_damage")
end

local function breath_due(m)
	local n = 4
	if m.hp < m.maxhp // 2 or m:has_field("heat") or m:has_field("sun") then n = 3 end   -- heat feeds it
	if m:has_field("rain") or m:has_field("downpour") then n = n + 1 end                 -- rain douses it
	return m.turn % n == 0
end

return {
	name = "Red Dragon",
	lore = [[
The red dragon sleeps on a hoard beneath the mountains past Endworld, and it has never
once been known to share a gold piece. Its fire melts plate and runs down the stone walls
of the cave in streams. Adventurers who come looking for its gold tend to leave it
behind, and sometimes their bones with it.]],
	icon = "red_dragon",
	level = 41,
	maxhp = 200, maxdam = 180, armor = 145,
	maxexp = 720, maxgold = 240,
	resist = { fire = 75, frost = -50, water = -25 },
	ward = { burning = 50 },
	maxmp = 147,
	spells = {
		-- gathers a fire breath every 4th turn (3rd under half or in the heat, 5th in the rain), then it lands and burns
		{ spell = "fire_breath", weight = 30, when = breath_due },
		-- "I will not die to a creature like YOU!": it enrages under a quarter of its life
		{ spell = "fury", weight = 20, when = function(m) return m.hp < m.maxhp // 4 and unraged(m) end },
	},
	speech = {
		start = {
			"You smell of ash already, little knight.", "Kneel, and I may yet make it quick.",
			{ text = "Another thief come for my gold? Your bones will join the others.", weight = 2 },
			chance = 70,
		},
		turn = {
			"Burn.", "Your bones will warm my hoard.",
			{ text = "You sway on your feet, {player}. Fall, and be done.", weight = 3, when = { foe_hp_below = 25 },
				once = "condition" },
			chance = 15,
		},
		winning = { "Your armor is melting, {player}.", "Is this all the realm sends me?", once = true, chance = 40 },
		losing = {
			"Insolent worm! You dare wound me?",
			{ text = "Enough! I will not die to a creature like YOU!", once = true, when = { hp_below = 15 } },
			chance = 45,
		},
		hurt = {
			"A scratch.", "You will pay for every scale.",
			{ text = "Poison... in MY veins?", weight = 3, once = true, when = { has = { "poison" } } },
			chance = 20,
		},
		death = { "My hoard... my... hoard...", chance = 80 },
		victory = { "Another bauble for the hoard.", chance = 85 },
	},
}
