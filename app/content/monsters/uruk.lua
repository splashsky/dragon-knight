-- app/content/monsters/uruk.lua :: the Uruk (the original game's monster 59).
local function buffed(m)
	return m:has_status("uber_damage")
end

return {
	name = "Uruk",
	lore = [[
The Uruk is a tall, disciplined soldier of the orc kind, found in the hills past Narcissa
in squads of six or eight. Unlike the lesser brutes, Uruks carry shields, keep their
line, and wait for orders from their captain. They have a grudge against the towns for
taking their pasture, and they say so loudly before a fight. Meet them in the open and
they close ranks; meet them in a narrow pass and they still close ranks.]],
	icon = "uruk",
	level = 20,
	maxhp = 68, maxdam = 58, armor = 44,
	maxexp = 146, maxgold = 49,
	maxmp = 70,
	spells = {
		-- opens with its war cry
		{ spell = "war_cry", weight = 4, when = function(m) return not buffed(m) end },
	},
	items = {
		-- eats one herb when wounded
		{ item = "herb", weight = 4, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	speech = {
		start = { "Halt! Name yourself, little man.", chance = 40 },
		turn = { "Shield up!", "Hold the line.", chance = 15 },
		winning = { "Your town will fall like your guard, {player}.", chance = 25 },
		hurt = { "Pain is nothing!", chance = 30 },
		losing = { "Fall back! Fall back!", chance = 35 },
		death = { "The pasture... was ours...", chance = 55 },
		victory = { "Carry him to the fire.", chance = 40 },
	},
}
