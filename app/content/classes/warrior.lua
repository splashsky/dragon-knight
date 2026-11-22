-- app/content/classes/warrior.lua :: the Warrior class (the original game's class 2).
-- Content file: plain data, synced into the classes tables (see docs/APP.md "Content").
-- Levels list the gains on reaching each level (HP without the milestone bonus and TP
-- come from app/lib/leveling.lua); spells are the keys of the spells learned at
-- that level (app/content/spells/<key>.lua).
return {
	name = "Warrior",
	-- one line per point on the help page
	description = [[
Medium level-ups
Medium hit points
Low magic points
High strength
Low dexterity
5 heal spells
8 hurt spells
4 sleep spells
5 +defense spells
6 +attack spells
4 affliction spells
2 ally spells
3 support spells]],
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
Warriors learn their trade on the long road between Midworld and Roma, where the slimes
are many and the inns are few. They trust steel over spells, and a good night's rest over
both. When the monsters of the far lands come down from the hills, it is a Warrior who
stands at the gate.]],
	sort = 2,
	playable = true,

	-- a new character's stats (attack and defense power start at strength and dexterity)
	start_hp = 15, start_mp = 0, start_tp = 10, start_strength = 5, start_dexterity = 5,

	-- experience from level 1 to 2; later steps follow the global curve (app/lib/leveling.lua;
	-- a class can set its own with exp_stages = "factor x steps,...")
	exp_base = 18,

	levels = {
		[2] = { hp = 2, mp = 4, strength = 2, dexterity = 1, spells = { "heal" } },
		[3] = { hp = 2, mp = 3, strength = 3, dexterity = 2, spells = { "war_cry" } },
		[4] = { hp = 2, mp = 3, strength = 3, dexterity = 2 },
		[5] = { hp = 2, mp = 4, strength = 2, dexterity = 1, spells = { "hurt" } },
		[6] = { hp = 3, mp = 4, strength = 4, dexterity = 3, spells = { "cleave" } },
		[7] = { hp = 2, mp = 3, strength = 3, dexterity = 2 },
		[8] = { hp = 2, mp = 3, strength = 2, dexterity = 1, spells = { "sleep" } },
		[9] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[10] = { hp = 0, mp = 2, strength = 6, dexterity = 3, spells = { "grit" } },
		[11] = { hp = 4, mp = 1, strength = 5, dexterity = 4, spells = { "revive" } },
		[12] = { hp = 4, mp = 1, strength = 4, dexterity = 3 },
		[13] = { hp = 4, mp = 2, strength = 4, dexterity = 3 },
		[14] = { hp = 4, mp = 3, strength = 5, dexterity = 4, spells = { "pain" } },
		[15] = { hp = 4, mp = 4, strength = 5, dexterity = 4 },
		[16] = { hp = 5, mp = 2, strength = 5, dexterity = 4 },
		[17] = { hp = 4, mp = 1, strength = 4, dexterity = 3, spells = { "stun" } },
		[18] = { hp = 3, mp = 1, strength = 4, dexterity = 3, spells = { "craze" } },
		[19] = { hp = 3, mp = 4, strength = 4, dexterity = 3 },
		[20] = { hp = 0, mp = 5, strength = 5, dexterity = 3, spells = { "blood_strike" } },
		[21] = { hp = 4, mp = 3, strength = 4, dexterity = 3, spells = { "mire" } },
		[22] = { hp = 4, mp = 4, strength = 5, dexterity = 4, spells = { "dream" } },
		[23] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[24] = { hp = 4, mp = 4, strength = 5, dexterity = 4, spells = { "call_bear" } },
		[25] = { hp = 3, mp = 3, strength = 4, dexterity = 3, spells = { "ward" } },
		[26] = { hp = 5, mp = 2, strength = 6, dexterity = 5 },
		[27] = { hp = 5, mp = 1, strength = 6, dexterity = 5 },
		[28] = { hp = 4, mp = 1, strength = 4, dexterity = 3, spells = { "reaver" } },
		[29] = { hp = 5, mp = 2, strength = 6, dexterity = 5, spells = { "life" } },
		[30] = { hp = 0, mp = 3, strength = 6, dexterity = 4, spells = { "stand_fast" } },
		[31] = { hp = 4, mp = 3, strength = 5, dexterity = 4 },
		[32] = { hp = 5, mp = 3, strength = 6, dexterity = 5, spells = { "tithe" } },
		[33] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[34] = { hp = 5, mp = 3, strength = 6, dexterity = 5, spells = { "maim" } },
		[35] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[36] = { hp = 5, mp = 2, strength = 4, dexterity = 3, spells = { "second_wind" } },
		[37] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[38] = { hp = 5, mp = 4, strength = 6, dexterity = 5, spells = { "rage" } },
		[39] = { hp = 5, mp = 3, strength = 6, dexterity = 5 },
		[40] = { hp = 0, mp = 2, strength = 7, dexterity = 5, spells = { "hunters_mark" } },
		[41] = { hp = 6, mp = 2, strength = 7, dexterity = 2 },
		[42] = { hp = 6, mp = 3, strength = 7, dexterity = 6, spells = { "last_stand" } },
		[43] = { hp = 7, mp = 4, strength = 8, dexterity = 7 },
		[44] = { hp = 5, mp = 2, strength = 6, dexterity = 5 },
		[45] = { hp = 5, mp = 8, strength = 5, dexterity = 4, spells = { "fend" } },
		[46] = { hp = 5, mp = 4, strength = 6, dexterity = 5 },
		[47] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[48] = { hp = 5, mp = 3, strength = 6, dexterity = 5, spells = { "enfeeble" } },
		[49] = { hp = 4, mp = 2, strength = 5, dexterity = 4 },
		[50] = { hp = 0, mp = 2, strength = 7, dexterity = 5 },
		[51] = { hp = 5, mp = 1, strength = 6, dexterity = 5, spells = { "nightmare" } },
		[52] = { hp = 6, mp = 1, strength = 7, dexterity = 6 },
		[53] = { hp = 7, mp = 1, strength = 8, dexterity = 7 },
		[54] = { hp = 7, mp = 3, strength = 8, dexterity = 7, spells = { "wellspring" } },
		[55] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[56] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[57] = { hp = 6, mp = 4, strength = 6, dexterity = 5 },
		[58] = { hp = 5, mp = 4, strength = 5, dexterity = 4, spells = { "barrier" } },
		[59] = { hp = 7, mp = 2, strength = 8, dexterity = 7 },
		[60] = { hp = 0, mp = 3, strength = 8, dexterity = 6, spells = { "finishing_blow" } },
		[61] = { hp = 7, mp = 4, strength = 8, dexterity = 7 },
		[62] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[63] = { hp = 8, mp = 4, strength = 9, dexterity = 8 },
		[64] = { hp = 5, mp = 4, strength = 5, dexterity = 4, spells = { "call_golem" } },
		[65] = { hp = 6, mp = 3, strength = 6, dexterity = 5 },
		[66] = { hp = 8, mp = 3, strength = 8, dexterity = 7 },
		[67] = { hp = 7, mp = 2, strength = 7, dexterity = 6 },
		[68] = { hp = 8, mp = 2, strength = 9, dexterity = 8 },
		[69] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[70] = { hp = 0, mp = 3, strength = 8, dexterity = 6, spells = { "fury" } },
		[71] = { hp = 5, mp = 4, strength = 5, dexterity = 4 },
		[72] = { hp = 5, mp = 1, strength = 6, dexterity = 5 },
		[73] = { hp = 8, mp = 3, strength = 8, dexterity = 7 },
		[74] = { hp = 6, mp = 4, strength = 7, dexterity = 6 },
		[75] = { hp = 5, mp = 2, strength = 5, dexterity = 4 },
		[76] = { hp = 6, mp = 2, strength = 6, dexterity = 5, spells = { "rockfall" } },
		[77] = { hp = 7, mp = 3, strength = 6, dexterity = 5 },
		[78] = { hp = 7, mp = 3, strength = 7, dexterity = 6 },
		[79] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[80] = { hp = 0, mp = 4, strength = 8, dexterity = 7 },
		[81] = { hp = 7, mp = 2, strength = 7, dexterity = 6 },
		[82] = { hp = 5, mp = 3, strength = 6, dexterity = 5, spells = { "venom" } },
		[83] = { hp = 6, mp = 1, strength = 6, dexterity = 5 },
		[84] = { hp = 5, mp = 3, strength = 5, dexterity = 4 },
		[85] = { hp = 6, mp = 3, strength = 7, dexterity = 6 },
		[86] = { hp = 8, mp = 4, strength = 8, dexterity = 7 },
		[87] = { hp = 7, mp = 3, strength = 8, dexterity = 7 },
		[88] = { hp = 8, mp = 4, strength = 9, dexterity = 8, spells = { "cleanse" } },
		[89] = { hp = 5, mp = 1, strength = 5, dexterity = 4 },
		[90] = { hp = 0, mp = 1, strength = 9, dexterity = 8 },
		[91] = { hp = 5, mp = 2, strength = 5, dexterity = 4 },
		[92] = { hp = 4, mp = 2, strength = 6, dexterity = 5 },
		[93] = { hp = 6, mp = 2, strength = 8, dexterity = 7 },
		[94] = { hp = 4, mp = 3, strength = 5, dexterity = 3, spells = { "curse" } },
		[95] = { hp = 4, mp = 2, strength = 7, dexterity = 2 },
		[96] = { hp = 5, mp = 2, strength = 7, dexterity = 3 },
		[97] = { hp = 5, mp = 3, strength = 7, dexterity = 5 },
		[98] = { hp = 4, mp = 3, strength = 7, dexterity = 3 },
		[99] = { hp = 0, mp = 3, strength = 9, dexterity = 5 },
		[100] = { hp = 0, mp = 0, strength = 0, dexterity = 0, spells = { "warlord" } },
	},
}
