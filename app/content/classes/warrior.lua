-- app/content/classes/warrior.lua :: the Warrior class (the original game's class 2).
-- Content file: plain data, synced into the classes tables (see docs/APP.md "Content").
-- Levels list the gains on reaching each level (HP without the milestone bonus and TP
-- come from app/lib/leveling.lua); spells are spell ids learned at that level.
return {
	name = "Warrior",
	-- one line per point on the help page
	description = [[
Medium level-ups
Medium hit points
Low magic points
High strength
Low dexterity
3 heal spells
3 hurt spells
2 sleep spells
3 +defense spells
3 +attack spells]],
	sort = 2,
	playable = true,

	-- a new character's stats (attack and defense power start at strength and dexterity)
	start_hp = 15, start_mp = 0, start_tp = 10, start_strength = 5, start_dexterity = 5,

	-- experience curve (app/lib/leveling.lua): the step from level 1 to 2, then each
	-- step is the previous one times a factor, for that many steps ("factor x steps")
	exp_base = 18,
	exp_stages = "2x2,1.5x8,1.25x5,1.125x27",

	levels = {
		[2] = { hp = 2, mp = 4, strength = 2, dexterity = 1, spells = { 1 } }, -- Heal
		[3] = { hp = 2, mp = 3, strength = 3, dexterity = 2 },
		[4] = { hp = 2, mp = 3, strength = 3, dexterity = 2 },
		[5] = { hp = 2, mp = 4, strength = 2, dexterity = 1, spells = { 6 } }, -- Hurt
		[6] = { hp = 3, mp = 4, strength = 4, dexterity = 3 },
		[7] = { hp = 2, mp = 3, strength = 3, dexterity = 2 },
		[8] = { hp = 2, mp = 3, strength = 2, dexterity = 1, spells = { 11 } }, -- Sleep
		[9] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[10] = { hp = 0, mp = 2, strength = 6, dexterity = 3 },
		[11] = { hp = 4, mp = 1, strength = 5, dexterity = 4, spells = { 2 } }, -- Revive
		[12] = { hp = 4, mp = 1, strength = 4, dexterity = 3 },
		[13] = { hp = 4, mp = 2, strength = 4, dexterity = 3 },
		[14] = { hp = 4, mp = 3, strength = 5, dexterity = 4, spells = { 7 } }, -- Pain
		[15] = { hp = 4, mp = 4, strength = 5, dexterity = 4 },
		[16] = { hp = 5, mp = 2, strength = 5, dexterity = 4 },
		[17] = { hp = 4, mp = 1, strength = 4, dexterity = 3 },
		[18] = { hp = 3, mp = 1, strength = 4, dexterity = 3, spells = { 14 } }, -- Craze
		[19] = { hp = 3, mp = 4, strength = 4, dexterity = 3 },
		[20] = { hp = 0, mp = 5, strength = 5, dexterity = 3 },
		[21] = { hp = 4, mp = 3, strength = 4, dexterity = 3 },
		[22] = { hp = 4, mp = 4, strength = 5, dexterity = 4, spells = { 12 } }, -- Dream
		[23] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[24] = { hp = 4, mp = 4, strength = 5, dexterity = 4 },
		[25] = { hp = 3, mp = 3, strength = 4, dexterity = 3, spells = { 17 } }, -- Ward
		[26] = { hp = 5, mp = 2, strength = 6, dexterity = 5 },
		[27] = { hp = 5, mp = 1, strength = 6, dexterity = 5 },
		[28] = { hp = 4, mp = 1, strength = 4, dexterity = 3 },
		[29] = { hp = 5, mp = 2, strength = 6, dexterity = 5, spells = { 3 } }, -- Life
		[30] = { hp = 0, mp = 3, strength = 6, dexterity = 4 },
		[31] = { hp = 4, mp = 3, strength = 5, dexterity = 4 },
		[32] = { hp = 5, mp = 3, strength = 6, dexterity = 5 },
		[33] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[34] = { hp = 5, mp = 3, strength = 6, dexterity = 5, spells = { 8 } }, -- Maim
		[35] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[36] = { hp = 5, mp = 2, strength = 4, dexterity = 3 },
		[37] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[38] = { hp = 5, mp = 4, strength = 6, dexterity = 5, spells = { 15 } }, -- Rage
		[39] = { hp = 5, mp = 3, strength = 6, dexterity = 5 },
		[40] = { hp = 0, mp = 2, strength = 7, dexterity = 5 },
		[41] = { hp = 6, mp = 2, strength = 7, dexterity = 2 },
		[42] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[43] = { hp = 7, mp = 4, strength = 8, dexterity = 7 },
		[44] = { hp = 5, mp = 2, strength = 6, dexterity = 5 },
		[45] = { hp = 5, mp = 8, strength = 5, dexterity = 4, spells = { 18 } }, -- Fend
		[46] = { hp = 5, mp = 4, strength = 6, dexterity = 5 },
		[47] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[48] = { hp = 5, mp = 3, strength = 6, dexterity = 5 },
		[49] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[50] = { hp = 0, mp = 2, strength = 7, dexterity = 5 },
		[51] = { hp = 5, mp = 1, strength = 6, dexterity = 5, spells = { 13 } }, -- Nightmare
		[52] = { hp = 6, mp = 1, strength = 7, dexterity = 6 },
		[53] = { hp = 7, mp = 1, strength = 8, dexterity = 7 },
		[54] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[55] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[56] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[57] = { hp = 6, mp = 4, strength = 6, dexterity = 5 },
		[58] = { hp = 5, mp = 4, strength = 5, dexterity = 4, spells = { 19 } }, -- Barrier
		[59] = { hp = 7, mp = 2, strength = 8, dexterity = 7 },
		[60] = { hp = 0, mp = 3, strength = 8, dexterity = 6 },
		[61] = { hp = 7, mp = 4, strength = 8, dexterity = 7 },
		[62] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[63] = { hp = 8, mp = 4, strength = 9, dexterity = 8 },
		[64] = { hp = 5, mp = 4, strength = 5, dexterity = 4 },
		[65] = { hp = 6, mp = 3, strength = 6, dexterity = 5 },
		[66] = { hp = 8, mp = 3, strength = 8, dexterity = 7 },
		[67] = { hp = 7, mp = 2, strength = 7, dexterity = 6 },
		[68] = { hp = 8, mp = 2, strength = 9, dexterity = 8 },
		[69] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[70] = { hp = 0, mp = 3, strength = 8, dexterity = 6, spells = { 16 } }, -- Fury
		[71] = { hp = 5, mp = 4, strength = 5, dexterity = 4 },
		[72] = { hp = 5, mp = 1, strength = 6, dexterity = 5 },
		[73] = { hp = 8, mp = 3, strength = 8, dexterity = 7 },
		[74] = { hp = 6, mp = 4, strength = 7, dexterity = 6 },
		[75] = { hp = 5, mp = 2, strength = 5, dexterity = 4 },
		[76] = { hp = 6, mp = 2, strength = 6, dexterity = 5 },
		[77] = { hp = 7, mp = 3, strength = 6, dexterity = 5 },
		[78] = { hp = 7, mp = 3, strength = 7, dexterity = 6 },
		[79] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[80] = { hp = 0, mp = 4, strength = 8, dexterity = 7 },
		[81] = { hp = 7, mp = 2, strength = 7, dexterity = 6 },
		[82] = { hp = 5, mp = 3, strength = 6, dexterity = 5 },
		[83] = { hp = 6, mp = 1, strength = 6, dexterity = 5 },
		[84] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[85] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[86] = { hp = 8, mp = 4, strength = 8, dexterity = 7 },
		[87] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[88] = { hp = 8, mp = 4, strength = 9, dexterity = 8 },
		[89] = { hp = 5, mp = 1, strength = 5, dexterity = 4 },
		[90] = { hp = 0, mp = 1, strength = 9, dexterity = 8 },
		[91] = { hp = 5, mp = 2, strength = 5, dexterity = 4 },
		[92] = { hp = 4, mp = 2, strength = 6, dexterity = 5 },
		[93] = { hp = 6, mp = 2, strength = 8, dexterity = 7 },
		[94] = { hp = 4, mp = 3, strength = 5, dexterity = 3 },
		[95] = { hp = 4, mp = 2, strength = 7, dexterity = 2 },
		[96] = { hp = 5, mp = 2, strength = 7, dexterity = 3 },
		[97] = { hp = 5, mp = 3, strength = 7, dexterity = 5 },
		[98] = { hp = 4, mp = 3, strength = 7, dexterity = 3 },
		[99] = { hp = 0, mp = 3, strength = 9, dexterity = 5 },
		[100] = { hp = 0, mp = 0, strength = 0, dexterity = 0 },
	},
}
