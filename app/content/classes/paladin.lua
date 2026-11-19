-- app/content/classes/paladin.lua :: the Paladin class (the original game's class 3).
-- Content file: plain data, synced into the classes tables (see docs/APP.md "Content").
-- Levels list the gains on reaching each level (HP without the milestone bonus and TP
-- come from app/lib/leveling.lua); spells are spell ids learned at that level.
return {
	name = "Paladin",
	-- one line per point on the help page
	description = [[
Slow level-ups
Medium hit points
Medium magic points
Low strength
High dexterity
4 heal spells
4 hurt spells
3 sleep spells
2 +defense spells
2 +attack spells]],
	sort = 3,
	playable = true,

	-- a new character's stats (attack and defense power start at strength and dexterity)
	start_hp = 15, start_mp = 0, start_tp = 10, start_strength = 5, start_dexterity = 5,

	-- experience curve (app/lib/leveling.lua): the step from level 1 to 2, then each
	-- step is the previous one times a factor, for that many steps ("factor x steps")
	exp_base = 20,
	exp_stages = "2x2,1.5x8,1.25x6,1.125x25",

	levels = {
		[2] = { hp = 2, mp = 5, strength = 0, dexterity = 2, spells = { 1 } }, -- Heal
		[3] = { hp = 2, mp = 3, strength = 1, dexterity = 3 },
		[4] = { hp = 2, mp = 4, strength = 1, dexterity = 3 },
		[5] = { hp = 2, mp = 4, strength = 0, dexterity = 2, spells = { 6 } }, -- Hurt
		[6] = { hp = 3, mp = 5, strength = 2, dexterity = 4 },
		[7] = { hp = 2, mp = 3, strength = 1, dexterity = 3 },
		[8] = { hp = 2, mp = 4, strength = 0, dexterity = 2, spells = { 11 } }, -- Sleep
		[9] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[10] = { hp = 0, mp = 3, strength = 4, dexterity = 4 },
		[11] = { hp = 4, mp = 1, strength = 3, dexterity = 5, spells = { 2 } }, -- Revive
		[12] = { hp = 4, mp = 2, strength = 2, dexterity = 4 },
		[13] = { hp = 4, mp = 2, strength = 2, dexterity = 4 },
		[14] = { hp = 4, mp = 4, strength = 3, dexterity = 5, spells = { 7 } }, -- Pain
		[15] = { hp = 4, mp = 4, strength = 3, dexterity = 5 },
		[16] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[17] = { hp = 4, mp = 1, strength = 2, dexterity = 4 },
		[18] = { hp = 3, mp = 2, strength = 2, dexterity = 4, spells = { 17 } }, -- Ward
		[19] = { hp = 3, mp = 4, strength = 2, dexterity = 4 },
		[20] = { hp = 0, mp = 6, strength = 3, dexterity = 4 },
		[21] = { hp = 4, mp = 3, strength = 2, dexterity = 4 },
		[22] = { hp = 4, mp = 5, strength = 3, dexterity = 5, spells = { 12 } }, -- Dream
		[23] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[24] = { hp = 4, mp = 5, strength = 3, dexterity = 5 },
		[25] = { hp = 3, mp = 3, strength = 2, dexterity = 4, spells = { 14 } }, -- Craze
		[26] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[27] = { hp = 5, mp = 1, strength = 4, dexterity = 6 },
		[28] = { hp = 4, mp = 2, strength = 2, dexterity = 4 },
		[29] = { hp = 5, mp = 2, strength = 4, dexterity = 6, spells = { 3 } }, -- Life
		[30] = { hp = 0, mp = 4, strength = 4, dexterity = 5 },
		[31] = { hp = 4, mp = 3, strength = 3, dexterity = 5 },
		[32] = { hp = 5, mp = 4, strength = 4, dexterity = 6 },
		[33] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[34] = { hp = 5, mp = 4, strength = 4, dexterity = 6, spells = { 8 } }, -- Maim
		[35] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[36] = { hp = 5, mp = 3, strength = 2, dexterity = 4 },
		[37] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[38] = { hp = 5, mp = 5, strength = 4, dexterity = 6, spells = { 18 } }, -- Fend
		[39] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[40] = { hp = 0, mp = 3, strength = 5, dexterity = 6 },
		[41] = { hp = 6, mp = 2, strength = 5, dexterity = 3 },
		[42] = { hp = 6, mp = 4, strength = 5, dexterity = 7 },
		[43] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[44] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[45] = { hp = 5, mp = 8, strength = 3, dexterity = 5, spells = { 4 } }, -- Breath
		[46] = { hp = 5, mp = 5, strength = 4, dexterity = 6 },
		[47] = { hp = 6, mp = 3, strength = 5, dexterity = 7 },
		[48] = { hp = 5, mp = 4, strength = 4, dexterity = 6 },
		[49] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[50] = { hp = 0, mp = 3, strength = 5, dexterity = 6 },
		[51] = { hp = 5, mp = 1, strength = 4, dexterity = 6, spells = { 13 } }, -- Nightmare
		[52] = { hp = 6, mp = 2, strength = 5, dexterity = 7 },
		[53] = { hp = 7, mp = 1, strength = 6, dexterity = 8 },
		[54] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[55] = { hp = 6, mp = 3, strength = 5, dexterity = 7 },
		[56] = { hp = 6, mp = 4, strength = 5, dexterity = 7, spells = { 9 } }, -- Rend
		[57] = { hp = 6, mp = 4, strength = 4, dexterity = 6 },
		[58] = { hp = 5, mp = 5, strength = 3, dexterity = 5 },
		[59] = { hp = 7, mp = 2, strength = 6, dexterity = 8 },
		[60] = { hp = 0, mp = 4, strength = 6, dexterity = 7, spells = { 15 } }, -- Rage
		[61] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[62] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[63] = { hp = 8, mp = 4, strength = 7, dexterity = 9 },
		[64] = { hp = 5, mp = 5, strength = 3, dexterity = 5 },
		[65] = { hp = 6, mp = 3, strength = 4, dexterity = 6 },
		[66] = { hp = 8, mp = 4, strength = 6, dexterity = 8 },
		[67] = { hp = 7, mp = 2, strength = 5, dexterity = 7 },
		[68] = { hp = 8, mp = 3, strength = 7, dexterity = 9 },
		[69] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[70] = { hp = 0, mp = 4, strength = 6, dexterity = 7 },
		[71] = { hp = 5, mp = 4, strength = 3, dexterity = 5 },
		[72] = { hp = 5, mp = 2, strength = 4, dexterity = 6 },
		[73] = { hp = 8, mp = 3, strength = 6, dexterity = 8 },
		[74] = { hp = 6, mp = 5, strength = 5, dexterity = 7 },
		[75] = { hp = 5, mp = 2, strength = 3, dexterity = 5 },
		[76] = { hp = 6, mp = 3, strength = 4, dexterity = 6 },
		[77] = { hp = 7, mp = 3, strength = 4, dexterity = 6 },
		[78] = { hp = 7, mp = 4, strength = 5, dexterity = 7 },
		[79] = { hp = 7, mp = 3, strength = 6, dexterity = 8 },
		[80] = { hp = 0, mp = 5, strength = 6, dexterity = 8 },
		[81] = { hp = 7, mp = 2, strength = 5, dexterity = 7 },
		[82] = { hp = 5, mp = 4, strength = 4, dexterity = 6 },
		[83] = { hp = 6, mp = 1, strength = 4, dexterity = 6 },
		[84] = { hp = 5, mp = 4, strength = 3, dexterity = 5 },
		[85] = { hp = 6, mp = 3, strength = 5, dexterity = 7 },
		[86] = { hp = 8, mp = 5, strength = 6, dexterity = 8 },
		[87] = { hp = 7, mp = 3, strength = 6, dexterity = 8 },
		[88] = { hp = 8, mp = 5, strength = 7, dexterity = 9 },
		[89] = { hp = 5, mp = 1, strength = 3, dexterity = 5 },
		[90] = { hp = 0, mp = 2, strength = 7, dexterity = 9 },
		[91] = { hp = 5, mp = 2, strength = 3, dexterity = 5 },
		[92] = { hp = 4, mp = 3, strength = 4, dexterity = 6 },
		[93] = { hp = 6, mp = 2, strength = 6, dexterity = 8 },
		[94] = { hp = 4, mp = 4, strength = 3, dexterity = 4 },
		[95] = { hp = 4, mp = 2, strength = 5, dexterity = 3 },
		[96] = { hp = 5, mp = 3, strength = 4, dexterity = 4 },
		[97] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[98] = { hp = 4, mp = 4, strength = 4, dexterity = 4 },
		[99] = { hp = 0, mp = 4, strength = 6, dexterity = 6 },
		[100] = { hp = 0, mp = 0, strength = 0, dexterity = 0 },
	},
}
