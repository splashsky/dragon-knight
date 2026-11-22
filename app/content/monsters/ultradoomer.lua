-- app/content/monsters/ultradoomer.lua :: the Ultradoomer (the original game's monster 106).
return {
	name = "Ultradoomer",
	lore = [[
The Megadoomer's elder, which stands in the dead hall beneath the Hambry road and keeps a
count that is nearly done. Its hood hides a face that nobody has described twice in the
same way. Scholars in Gilead say the count is the only real thing about it, and that when
it reaches its end the road will be quieter for a while.]],
	icon = "ultradoomer",
	level = 36,
	maxhp = 155, maxdam = 140, armor = 115,
	maxexp = 395, maxgold = 132,
	resist = { shadow = 75, poison = 100, frost = 25, holy = -75 },
	ward = { poison = 100, sleep = 100 },
	maxmp = 128,
	spells = {
		-- "Four. Three. Two. One. Zero.": a four-turn countdown, then shadow damage; it hurries a new one under a third of its life
		{ spell = "doom", weight = 30, when = function(m)
			return not m.target:has_status("doom") and (m.turn % 5 == 1 or m.hp < m.maxhp // 3)
		end },
	},
	speech = {
		start = { "Four.", "Three. You are already counted.", chance = 40 },
		turn = {
			"Two.", "One is close.",
			{ text = "Your count is running, {player}.", when = { foe_has = { "doom" } } },
			{ text = "Listen. The number is falling.", when = { foe_has = { "doom" } } },
			chance = 15,
		},
		winning = { "Zero... and the road is quiet.", chance = 35 },
		losing = { "The count is not yours to stop.", chance = 35 },
		hurt = { "Hold, I am still counting!", chance = 20 },
		death = { "Zero.", chance = 70 },
		victory = { "The count is complete.", chance = 55 },
	},
}
