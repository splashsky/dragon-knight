-- app/content/monsters/bandit.lua :: the Bandit (the original game's monster 47).
return {
	name = "Bandit",
	lore = [[
A roadside robber in a patched cloak, with a club or a short sword and a habit of waiting among
the rocks. Bandits work in bands of five or six and seldom fight once they have had their pick
of the wagon. The reason caravans now travel with guards is mostly them.]],
	icon = "bandit",
	level = 16,
	maxhp = 52, maxdam = 45, armor = 30,
	maxexp = 114, maxgold = 38,
	maxmp = 55,
	attack_weight = 4,
	items = {
		-- throws an Acid Vial from its second turn on
		{ item = "acid_vial", weight = 2, stock = 1, when = function(m) return m.turn >= 2 end },
		-- eats a herb under a third of its HP
		{ item = "herb", weight = 3, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	speech = {
		start = { "Stand and deliver! Hand it over!", chance = 50 },
		turn = { "Don't make us do this the hard way.", "Keep your hands where I can see them.", chance = 25 },
		winning = { "Easy, that was. Easy.", chance = 30 },
		losing = { "Run! Run for the rocks!", chance = 40 },
		hurt = { "Ow! That's my good cloak!", chance = 30 },
		death = { "Tell Ned I... never mind.", chance = 60 },
		victory = { "That's the wagon, lads!", chance = 50 },
	},
}
