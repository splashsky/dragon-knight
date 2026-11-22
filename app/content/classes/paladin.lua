-- app/content/classes/paladin.lua :: the Paladin class (the original game's class 3).
-- Content file: plain data, synced into the classes tables (see docs/APP.md "Content").
-- Levels list the gains on reaching each level (HP without the milestone bonus and TP
-- come from app/lib/leveling.lua); spells are the keys of the spells learned at
-- that level (app/content/spells/<key>.lua).
return {
	name = "Paladin",
	-- one line per point on the help page
	description = [[
Slow level-ups
Medium hit points
Medium magic points
Low strength
High dexterity
8 heal spells
8 hurt spells
3 sleep spells
3 +defense spells
3 +attack spells
3 affliction spells
3 ally spells
3 support spells]],
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The Paladins keep an oath sworn before the first dragon fell: to carry light into every
dark place on the map. Their prayers are slower than a Mage's words and their arms slower
than a Warrior's blade, but they rarely fall, and they never leave a companion behind.]],
	sort = 3,
	playable = true,

	-- a new character's stats (attack and defense power start at strength and dexterity)
	start_hp = 15, start_mp = 0, start_tp = 10, start_strength = 5, start_dexterity = 5,

	-- experience from level 1 to 2; later steps follow the global curve (app/lib/leveling.lua;
	-- a class can set its own with exp_stages = "factor x steps,...")
	exp_base = 20,

	levels = {
		[2] = { hp = 2, mp = 5, strength = 0, dexterity = 2, spells = { "heal" } },
		[3] = { hp = 2, mp = 3, strength = 1, dexterity = 3, spells = { "cleanse" } },
		[4] = { hp = 2, mp = 4, strength = 1, dexterity = 3 },
		[5] = { hp = 2, mp = 4, strength = 0, dexterity = 2, spells = { "hurt" } },
		[6] = { hp = 3, mp = 5, strength = 2, dexterity = 4 },
		[7] = { hp = 2, mp = 3, strength = 1, dexterity = 3 },
		[8] = { hp = 2, mp = 4, strength = 0, dexterity = 2, spells = { "sleep" } },
		[9] = { hp = 4, mp = 2, strength = 3, dexterity = 5, spells = { "mend" } },
		[10] = { hp = 0, mp = 3, strength = 4, dexterity = 4 },
		[11] = { hp = 4, mp = 1, strength = 3, dexterity = 5, spells = { "revive" } },
		[12] = { hp = 4, mp = 2, strength = 2, dexterity = 4, spells = { "enfeeble" } },
		[13] = { hp = 4, mp = 2, strength = 2, dexterity = 4 },
		[14] = { hp = 4, mp = 4, strength = 3, dexterity = 5, spells = { "pain" } },
		[15] = { hp = 4, mp = 4, strength = 3, dexterity = 5 },
		[16] = { hp = 5, mp = 3, strength = 3, dexterity = 5, spells = { "dawnstrike" } },
		[17] = { hp = 4, mp = 1, strength = 2, dexterity = 4 },
		[18] = { hp = 3, mp = 2, strength = 2, dexterity = 4, spells = { "ward" } },
		[19] = { hp = 3, mp = 4, strength = 2, dexterity = 4 },
		[20] = { hp = 0, mp = 6, strength = 3, dexterity = 4, spells = { "mercy" } },
		[21] = { hp = 4, mp = 3, strength = 2, dexterity = 4, spells = { "fire_ward" } },
		[22] = { hp = 4, mp = 5, strength = 3, dexterity = 5, spells = { "dream" } },
		[23] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[24] = { hp = 4, mp = 5, strength = 3, dexterity = 5, spells = { "frost_ward" } },
		[25] = { hp = 3, mp = 3, strength = 2, dexterity = 4, spells = { "craze" } },
		[26] = { hp = 5, mp = 3, strength = 4, dexterity = 6, spells = { "storm_ward" } },
		[27] = { hp = 5, mp = 1, strength = 4, dexterity = 6, spells = { "call_bear" } },
		[28] = { hp = 4, mp = 2, strength = 2, dexterity = 4 },
		[29] = { hp = 5, mp = 2, strength = 4, dexterity = 6, spells = { "life" } },
		[30] = { hp = 0, mp = 4, strength = 4, dexterity = 5, spells = { "consecrate" } },
		[31] = { hp = 4, mp = 3, strength = 3, dexterity = 5, spells = { "reaver" } },
		[32] = { hp = 5, mp = 4, strength = 4, dexterity = 6 },
		[33] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[34] = { hp = 5, mp = 4, strength = 4, dexterity = 6, spells = { "maim" } },
		[35] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[36] = { hp = 5, mp = 3, strength = 2, dexterity = 4, spells = { "tithe" } },
		[37] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[38] = { hp = 5, mp = 5, strength = 4, dexterity = 6, spells = { "fend" } },
		[39] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[40] = { hp = 0, mp = 3, strength = 5, dexterity = 6 },
		[41] = { hp = 6, mp = 2, strength = 5, dexterity = 3, spells = { "call_spirit" } },
		[42] = { hp = 6, mp = 4, strength = 5, dexterity = 7 },
		[43] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[44] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[45] = { hp = 5, mp = 8, strength = 3, dexterity = 5, spells = { "breath" } },
		[46] = { hp = 5, mp = 5, strength = 4, dexterity = 6 },
		[47] = { hp = 6, mp = 3, strength = 5, dexterity = 7 },
		[48] = { hp = 5, mp = 4, strength = 4, dexterity = 6, spells = { "iron_vigil" } },
		[49] = { hp = 4, mp = 2, strength = 3, dexterity = 5 },
		[50] = { hp = 0, mp = 3, strength = 5, dexterity = 6 },
		[51] = { hp = 5, mp = 1, strength = 4, dexterity = 6, spells = { "nightmare" } },
		[52] = { hp = 6, mp = 2, strength = 5, dexterity = 7 },
		[53] = { hp = 7, mp = 1, strength = 6, dexterity = 8, spells = { "withering" } },
		[54] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[55] = { hp = 6, mp = 3, strength = 5, dexterity = 7 },
		[56] = { hp = 6, mp = 4, strength = 5, dexterity = 7, spells = { "rend" } },
		[57] = { hp = 6, mp = 4, strength = 4, dexterity = 6 },
		[58] = { hp = 5, mp = 5, strength = 3, dexterity = 5, spells = { "radiance" } },
		[59] = { hp = 7, mp = 2, strength = 6, dexterity = 8 },
		[60] = { hp = 0, mp = 4, strength = 6, dexterity = 7, spells = { "rage" } },
		[61] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[62] = { hp = 7, mp = 4, strength = 6, dexterity = 8 },
		[63] = { hp = 8, mp = 4, strength = 7, dexterity = 9 },
		[64] = { hp = 5, mp = 5, strength = 3, dexterity = 5, spells = { "judgement" } },
		[65] = { hp = 6, mp = 3, strength = 4, dexterity = 6 },
		[66] = { hp = 8, mp = 4, strength = 6, dexterity = 8 },
		[67] = { hp = 7, mp = 2, strength = 5, dexterity = 7 },
		[68] = { hp = 8, mp = 3, strength = 7, dexterity = 9, spells = { "call_golem" } },
		[69] = { hp = 5, mp = 3, strength = 3, dexterity = 5 },
		[70] = { hp = 0, mp = 4, strength = 6, dexterity = 7 },
		[71] = { hp = 5, mp = 4, strength = 3, dexterity = 5 },
		[72] = { hp = 5, mp = 2, strength = 4, dexterity = 6, spells = { "renewal" } },
		[73] = { hp = 8, mp = 3, strength = 6, dexterity = 8 },
		[74] = { hp = 6, mp = 5, strength = 5, dexterity = 7 },
		[75] = { hp = 5, mp = 2, strength = 3, dexterity = 5 },
		[76] = { hp = 6, mp = 3, strength = 4, dexterity = 6, spells = { "wellspring" } },
		[77] = { hp = 7, mp = 3, strength = 4, dexterity = 6 },
		[78] = { hp = 7, mp = 4, strength = 5, dexterity = 7 },
		[79] = { hp = 7, mp = 3, strength = 6, dexterity = 8 },
		[80] = { hp = 0, mp = 5, strength = 6, dexterity = 8, spells = { "curse" } },
		[81] = { hp = 7, mp = 2, strength = 5, dexterity = 7 },
		[82] = { hp = 5, mp = 4, strength = 4, dexterity = 6 },
		[83] = { hp = 6, mp = 1, strength = 4, dexterity = 6 },
		[84] = { hp = 5, mp = 4, strength = 3, dexterity = 5, spells = { "finishing_blow" } },
		[85] = { hp = 6, mp = 3, strength = 5, dexterity = 7 },
		[86] = { hp = 8, mp = 5, strength = 6, dexterity = 8 },
		[87] = { hp = 7, mp = 3, strength = 6, dexterity = 8 },
		[88] = { hp = 8, mp = 5, strength = 7, dexterity = 9 },
		[89] = { hp = 5, mp = 1, strength = 3, dexterity = 5 },
		[90] = { hp = 0, mp = 2, strength = 7, dexterity = 9, spells = { "dawn" } },
		[91] = { hp = 5, mp = 2, strength = 3, dexterity = 5 },
		[92] = { hp = 4, mp = 3, strength = 4, dexterity = 6 },
		[93] = { hp = 6, mp = 2, strength = 6, dexterity = 8 },
		[94] = { hp = 4, mp = 4, strength = 3, dexterity = 4 },
		[95] = { hp = 4, mp = 2, strength = 5, dexterity = 3 },
		[96] = { hp = 5, mp = 3, strength = 4, dexterity = 4, spells = { "last_stand" } },
		[97] = { hp = 5, mp = 3, strength = 4, dexterity = 6 },
		[98] = { hp = 4, mp = 4, strength = 4, dexterity = 4 },
		[99] = { hp = 0, mp = 4, strength = 6, dexterity = 6 },
		[100] = { hp = 0, mp = 0, strength = 0, dexterity = 0 },
	},
}
