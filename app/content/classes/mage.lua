-- app/content/classes/mage.lua :: the Mage class (the original game's class 1).
-- Content file: plain data, synced into the classes tables (see docs/APP.md "Content").
-- Levels list the gains on reaching each level (HP without the milestone bonus and TP
-- come from app/lib/leveling.lua); spells are the keys of the spells learned at
-- that level (app/content/spells/<key>.lua).
return {
	name = "Mage",
	-- one line per point on the help page
	description = [[
Fast level-ups
High hit points
High magic points
Low strength
Low dexterity
6 heal spells
14 hurt spells (Magic Bolt from the start)
3 sleep spells
3 +defense spells
0 +attack spells
7 affliction spells
2 ally spells
3 support spells]],
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
In the towers of Midworld the old masters still teach the words that bend the world: a
whisper that closes wounds, a cry that calls down fire. Mages are frail in a brawl, and
every adventurer they have saved will tell you so. Few of them mind.]],
	sort = 1,
	playable = true,

	-- a new character's stats (attack and defense power start at strength and dexterity)
	start_hp = 15, start_mp = 5, start_tp = 10, start_strength = 5, start_dexterity = 5,
	-- keys of the spells a new character knows (learned at level 1)
	start_spells = { "magic_bolt" },

	-- experience from level 1 to 2; later steps follow the global curve (app/lib/leveling.lua;
	-- a class can set its own with exp_stages = "factor x steps,...")
	exp_base = 15,

	levels = {
		[2] = { hp = 2, mp = 5, strength = 0, dexterity = 1, spells = { "heal" } },
		[3] = { hp = 3, mp = 4, strength = 1, dexterity = 2 },
		[4] = { hp = 3, mp = 3, strength = 1, dexterity = 2, spells = { "hurt" } },
		[5] = { hp = 2, mp = 5, strength = 0, dexterity = 1 },
		[6] = { hp = 4, mp = 5, strength = 2, dexterity = 3, spells = { "spark" } },
		[7] = { hp = 3, mp = 4, strength = 1, dexterity = 2, spells = { "sleep" } },
		[8] = { hp = 2, mp = 4, strength = 0, dexterity = 1 },
		[9] = { hp = 5, mp = 3, strength = 3, dexterity = 4, spells = { "revive" } },
		[10] = { hp = 0, mp = 3, strength = 4, dexterity = 3, spells = { "enfeeble" } },
		[11] = { hp = 5, mp = 2, strength = 3, dexterity = 4 },
		[12] = { hp = 4, mp = 2, strength = 2, dexterity = 3, spells = { "pain" } },
		[13] = { hp = 4, mp = 3, strength = 2, dexterity = 3 },
		[14] = { hp = 5, mp = 4, strength = 3, dexterity = 4, spells = { "ward" } },
		[15] = { hp = 5, mp = 5, strength = 3, dexterity = 4 },
		[16] = { hp = 5, mp = 3, strength = 3, dexterity = 4, spells = { "frostbite" } },
		[17] = { hp = 4, mp = 2, strength = 2, dexterity = 3, spells = { "dream" } },
		[18] = { hp = 4, mp = 2, strength = 2, dexterity = 3 },
		[19] = { hp = 4, mp = 5, strength = 2, dexterity = 3, spells = { "ember" } },
		[20] = { hp = 0, mp = 6, strength = 3, dexterity = 3, spells = { "rain_call" } },
		[21] = { hp = 4, mp = 4, strength = 2, dexterity = 3, spells = { "wellspring" } },
		[22] = { hp = 5, mp = 5, strength = 3, dexterity = 4, spells = { "gust" } },
		[23] = { hp = 5, mp = 3, strength = 3, dexterity = 4, spells = { "cinder_lash" } },
		[24] = { hp = 5, mp = 5, strength = 3, dexterity = 4, spells = { "torrent" } },
		[25] = { hp = 4, mp = 4, strength = 2, dexterity = 3, spells = { "life" } },
		[26] = { hp = 6, mp = 3, strength = 4, dexterity = 5, spells = { "sunfire" } },
		[27] = { hp = 6, mp = 2, strength = 4, dexterity = 5, spells = { "cleanse" } },
		[28] = { hp = 4, mp = 2, strength = 2, dexterity = 3, spells = { "cold_snap" } },
		[29] = { hp = 6, mp = 3, strength = 4, dexterity = 5, spells = { "sap_mind" } },
		[30] = { hp = 0, mp = 4, strength = 4, dexterity = 4 },
		[31] = { hp = 5, mp = 5, strength = 3, dexterity = 4, spells = { "maim" } },
		[32] = { hp = 6, mp = 4, strength = 4, dexterity = 5, spells = { "gale" } },
		[33] = { hp = 5, mp = 4, strength = 3, dexterity = 4, spells = { "venom" } },
		[34] = { hp = 6, mp = 4, strength = 4, dexterity = 5, spells = { "fire_ward" } },
		[35] = { hp = 5, mp = 3, strength = 3, dexterity = 4, spells = { "call_spirit" } },
		[36] = { hp = 4, mp = 3, strength = 2, dexterity = 3, spells = { "fend" } },
		[37] = { hp = 5, mp = 4, strength = 3, dexterity = 4, spells = { "frost_ward" } },
		[38] = { hp = 6, mp = 5, strength = 4, dexterity = 5, spells = { "storm_ward" } },
		[39] = { hp = 6, mp = 4, strength = 4, dexterity = 5 },
		[40] = { hp = 0, mp = 3, strength = 5, dexterity = 5, spells = { "nightmare" } },
		[41] = { hp = 7, mp = 3, strength = 5, dexterity = 2, spells = { "storm_call" } },
		[42] = { hp = 7, mp = 4, strength = 5, dexterity = 6, spells = { "rockfall" } },
		[43] = { hp = 8, mp = 5, strength = 6, dexterity = 7 },
		[44] = { hp = 6, mp = 3, strength = 4, dexterity = 5 },
		[45] = { hp = 5, mp = 8, strength = 3, dexterity = 4, spells = { "breath", "scorch" } },
		[46] = { hp = 6, mp = 5, strength = 4, dexterity = 5, spells = { "hail" } },
		[47] = { hp = 7, mp = 4, strength = 5, dexterity = 6 },
		[48] = { hp = 6, mp = 4, strength = 4, dexterity = 5 },
		[49] = { hp = 5, mp = 3, strength = 3, dexterity = 4 },
		[50] = { hp = 0, mp = 3, strength = 5, dexterity = 5 },
		[51] = { hp = 6, mp = 2, strength = 4, dexterity = 5, spells = { "rend" } },
		[52] = { hp = 7, mp = 2, strength = 5, dexterity = 6, spells = { "cyclone" } },
		[53] = { hp = 8, mp = 2, strength = 6, dexterity = 7 },
		[54] = { hp = 8, mp = 4, strength = 6, dexterity = 7, spells = { "withering" } },
		[55] = { hp = 7, mp = 4, strength = 5, dexterity = 6 },
		[56] = { hp = 7, mp = 4, strength = 5, dexterity = 6 },
		[57] = { hp = 6, mp = 5, strength = 4, dexterity = 5, spells = { "tithe" } },
		[58] = { hp = 5, mp = 5, strength = 3, dexterity = 4 },
		[59] = { hp = 8, mp = 3, strength = 6, dexterity = 7 },
		[60] = { hp = 0, mp = 4, strength = 6, dexterity = 6, spells = { "barrier" } },
		[61] = { hp = 8, mp = 5, strength = 6, dexterity = 7 },
		[62] = { hp = 8, mp = 4, strength = 6, dexterity = 7, spells = { "lightning_lance" } },
		[63] = { hp = 9, mp = 5, strength = 7, dexterity = 8 },
		[64] = { hp = 5, mp = 5, strength = 3, dexterity = 4 },
		[65] = { hp = 6, mp = 4, strength = 4, dexterity = 5, spells = { "renewal" } },
		[66] = { hp = 8, mp = 4, strength = 6, dexterity = 7 },
		[67] = { hp = 7, mp = 3, strength = 5, dexterity = 6 },
		[68] = { hp = 9, mp = 3, strength = 7, dexterity = 8 },
		[69] = { hp = 5, mp = 4, strength = 3, dexterity = 4 },
		[70] = { hp = 0, mp = 4, strength = 6, dexterity = 6, spells = { "gaia" } },
		[71] = { hp = 5, mp = 5, strength = 3, dexterity = 4 },
		[72] = { hp = 6, mp = 2, strength = 4, dexterity = 5 },
		[73] = { hp = 8, mp = 4, strength = 6, dexterity = 7, spells = { "curse" } },
		[74] = { hp = 7, mp = 5, strength = 5, dexterity = 6 },
		[75] = { hp = 5, mp = 3, strength = 3, dexterity = 4 },
		[76] = { hp = 6, mp = 3, strength = 4, dexterity = 5, spells = { "starfall" } },
		[77] = { hp = 6, mp = 4, strength = 4, dexterity = 5 },
		[78] = { hp = 7, mp = 4, strength = 5, dexterity = 6 },
		[79] = { hp = 8, mp = 4, strength = 6, dexterity = 7, spells = { "chaos" } },
		[80] = { hp = 0, mp = 5, strength = 6, dexterity = 7 },
		[81] = { hp = 7, mp = 3, strength = 5, dexterity = 6 },
		[82] = { hp = 6, mp = 4, strength = 4, dexterity = 5 },
		[83] = { hp = 6, mp = 2, strength = 4, dexterity = 5, spells = { "plague" } },
		[84] = { hp = 5, mp = 4, strength = 3, dexterity = 4 },
		[85] = { hp = 7, mp = 4, strength = 5, dexterity = 6 },
		[86] = { hp = 8, mp = 5, strength = 6, dexterity = 7 },
		[87] = { hp = 8, mp = 4, strength = 6, dexterity = 7 },
		[88] = { hp = 9, mp = 5, strength = 7, dexterity = 8, spells = { "inferno" } },
		[89] = { hp = 5, mp = 2, strength = 3, dexterity = 4 },
		[90] = { hp = 0, mp = 2, strength = 7, dexterity = 8 },
		[91] = { hp = 5, mp = 3, strength = 3, dexterity = 4 },
		[92] = { hp = 6, mp = 3, strength = 4, dexterity = 5 },
		[93] = { hp = 8, mp = 4, strength = 6, dexterity = 7 },
		[94] = { hp = 4, mp = 4, strength = 3, dexterity = 3, spells = { "call_golem" } },
		[95] = { hp = 3, mp = 3, strength = 5, dexterity = 2 },
		[96] = { hp = 5, mp = 3, strength = 4, dexterity = 3 },
		[97] = { hp = 5, mp = 4, strength = 4, dexterity = 5 },
		[98] = { hp = 4, mp = 5, strength = 4, dexterity = 3 },
		[99] = { hp = 0, mp = 5, strength = 6, dexterity = 5 },
		[100] = { hp = 0, mp = 0, strength = 0, dexterity = 0, spells = { "whiteout" } },
	},
}
