-- app/content/monsters/cherufiend.lua :: the Cherufiend (the original game's monster 120).
return {
	name = "Cherufiend",
	lore = [[
A devil that was once a guard of the pit gates and still stands like one, with a shield
in one hand and a chain in the other. Cherufiends hold the stairs that lead from the mines
down to the deeper pits, and they check every visitor's papers before they let one pass.
Most adventurers prefer to fight their way through, which is what the Cherufiends expect.]],
	level = 41,
	maxhp = 195, maxdam = 170, armor = 140,
	maxexp = 690, maxgold = 230,
	immune = 0,
	maxmp = 147,
	speech = {
		start = { "Papers, {player}. Now.", "Nobody passes the stairs.", chance = 50 },
		turn = { "Stand still.", "Your papers are not in order.", chance = 15 },
		winning = { "The stairs stay closed.", chance = 35 },
		losing = { "I hold the gate! I always hold the gate!", chance = 40 },
		hurt = { "Dented, not down.", chance = 22 },
		death = { "The gate... is open...", chance = 65 },
		victory = { "Next visitor.", chance = 55 },
	},
}
