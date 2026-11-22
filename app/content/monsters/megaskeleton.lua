-- app/content/monsters/megaskeleton.lua :: the Megaskeleton (the original game's monster 37).
return {
	name = "Megaskeleton",
	lore = [[
Several skeletons fused together by a careless necromancer, which left it bigger, heavier and a
little confused. It shambles down the old roads near Kalle dragging a cart of bones it has
collected. It has no name, but the bones still remember how to fight.]],
	icon = "megaskeleton",
	level = 13,
	maxhp = 44, maxdam = 36, armor = 24,
	maxexp = 78, maxgold = 26,
	resist = { shadow = 50, poison = 100, holy = -50 },
	ward = { sleep = 100, poison = 100 },
	maxmp = 43,                         -- the Mage's MP at level 13: exactly one Life (25 MP)
	spells = {
		-- reassembles once, under a third of its HP
		{ spell = "life", weight = 6, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	speech = {
		start = { "*rattles loudly*", "*clatters, many bones at once*", chance = 30 },
		turn = { "*clack clack*", chance = 15 },
		winning = { "*rattles*", chance = 25 },
		losing = { "*clatter*", chance = 25 },
		hurt = { "*rattles angrily*", chance = 20 },
		death = { "*comes apart in many pieces*", chance = 60 },
		victory = { "*rattles*", chance = 30 },
	},
}
