-- app/content/monsters/bandit_captain.lua :: an example monster (new in 2.2) in full gear:
-- its equipment's attack, defense and modifiers count like a character's (maxdam 20 +
-- 45, armor 12 + 30 + 10, maxhp 120 + 25). It works itself into a frenzy once per fight
-- and eats its one herb when badly hurt. It doesn't roam (see goblin_shaman.lua).
return {
	name = "Bandit Captain",
	lore = [[
The leader of a bandit band, wearing a chain mail coat taken from a knight he robbed. He keeps
his men in line with a loud voice and a sharp sword, and he carries one herb in a pouch for when
he is hurt. Roadside notices offer gold for his head, and most of them are old.]],
	icon = "bandit_captain",
	description = "Well armed and armored; works itself into a frenzy and keeps a herb for emergencies.",
	level = 12,
	maxhp = 120, maxdam = 20, armor = 12,
	maxexp = 60, maxgold = 120,
	maxmp = 40,                         -- the Mage's MP at level 12
	roams = false,
	attack_weight = 4,
	equipment = {
		weapon = "broadsword",
		armor = "chain_mail",
		shield = "small_shield",
		accessory1 = "life_stone",
	},
	spells = {
		{ spell = "craze", weight = 1, when = function(m) return not m:has_status("uber_damage") end },
	},
	items = {
		{ item = "herb", weight = 2, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	speech = {
		start = { "Hold, travellers! Your purses are ours.", chance = 50 },
		turn = { "Keep moving, you lot. Nobody leaves.", "Eyes on the target!", chance = 25 },
		winning = { "Pick them clean, lads!", chance = 30 },
		losing = { "Retreat? Retreat is for cowards!", chance = 35 },
		hurt = { "That's a fine blow. Fine.", chance = 30 },
		death = { "Tell the band... they owe me nothing...", chance = 60 },
		victory = { "Split it three ways. No, four.", chance = 60 },
	},
}
