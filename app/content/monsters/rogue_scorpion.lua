-- app/content/monsters/rogue_scorpion.lua :: the Rogue Scorpion (the original game's monster 19).
local function unpoisoned(m)
	return not m.target:has_status("poison")
end

return {
	name = "Rogue Scorpion",
	lore = [[
A scorpion that left the desert and took up thieving, mostly in the caravan camps south of
Roma. It is cleverer than its cousins, and will dart in to take a purse or a pouch before
you blink. Merchants in Roma keep their coin in locked chests and pay the guards to watch
the stables.]],
	icon = "rogue_scorpion",
	level = 7,
	maxhp = 28, maxdam = 22, armor = 9,
	maxexp = 32, maxgold = 11,
	resist = { poison = 50, fire = -25 },
	ward = { poison = 100 },
	attack_element = "poison",
	maxmp = 26,
	spells = {
		-- opens by poisoning you, within its first two turns
		{ spell = "poison", weight = 5, when = function(m)
			return m.turn <= 2 and unpoisoned(m)
		end },
	},
	speech = {
		start = { "Your purse, friend, or your tail.", chance = 30 },
		turn = { "Quick now. Quick.", "*claws pick at your pack*", chance = 15 },
		hurt = { "Ow! Sneaky, that.", chance = 25 },
		losing = { "Bah. Not worth the trouble.", chance = 25 },
		death = { "*clicks once, faintly*", chance = 30 },
		victory = { "Pockets full, {player}!", chance = 25 },
	},
}
