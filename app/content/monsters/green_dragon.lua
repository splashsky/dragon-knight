-- app/content/monsters/green_dragon.lua :: the Green Dragon (the original game's monster 108).

local function breath_due(m)
	local n = m:has_field("fog") and 3 or 4        -- it hides in the fog
	return m.turn % n == 0
end

return {
	name = "Green Dragon",
	lore = [[
The green dragon lairs in the marsh-forest beyond Hambry, where the fog hides it until it
is already overhead. Its breath is a sour green cloud that clings to armour and lungs for
days after the fight. Hunters say the dragon takes only the gold it is owed and leaves the
rest, which is more than most lords can claim.]],
	icon = "green_dragon",
	level = 36,
	maxhp = 160, maxdam = 140, armor = 115,
	maxexp = 425, maxgold = 142,
	resist = { poison = 100, earth = 25, fire = -25 },
	ward = { poison = 100, venom = 100 },
	maxmp = 128,
	spells = {
		-- gathers a poison cloud every 4th turn, every 3rd in fog: a "Charging" tell, then it lands
		{ spell = "venom_breath", weight = 30, when = breath_due },
	},
	speech = {
		start = { "The fog brought you, little knight. Good.", "Stay a while. The air is thick here.", chance = 60 },
		turn = {
			"Breathe deep.", "Your lungs will remember this.",
			{ text = "The fog is mine. You will not see the next breath coming.", when = function(m) return m:has_field("fog") end },
			chance = 15,
		},
		winning = { "The marsh always wins in the end.", chance = 35 },
		losing = { "A scratch? I have had worse from gnats!", chance = 40 },
		hurt = { "The air stings, but I do not choke.", chance = 20 },
		status = { charging = { "*draws in a long, wet breath*", chance = 80 } },
		death = { "The fog... will... lift without me...", chance = 75 },
		victory = { "Another name for the marsh.", chance = 70 },
	},
}
