-- app/content/monsters/advocate.lua :: the Advocate (the original game's monster 103).
return {
	name = "Advocate",
	lore = [[
The first of the four pleaders of the hall in Hambry, who sit in judgement on anyone who
comes in without a receipt. An Advocate will argue your case for you, and will argue it
into the ground. Those who have been through the hall say it is safer to bring a witness
and a bag of coin.]],
	icon = "advocate",
	level = 35,
	maxhp = 148, maxdam = 132, armor = 108,
	maxexp = 350, maxgold = 117,
	ward = { weakened = 50 },                        -- hard to talk down
	maxmp = 125,
	attack_weight = 3,
	spells = {
		-- "argues your case into the ground": saps your strength for a few turns
		{ spell = "enfeeble", weight = 3, when = function(m) return not m.target:has_status("weakened") end },
	},
	speech = {
		start = { "You are charged, {player}.", "State your name for the record.", chance = 50 },
		turn = { "Objection.", "The record shows you struck first.", chance = 20 },
		winning = { "The court finds for the defence. Which is me.", chance = 35 },
		losing = { "I will appeal this.", "Strike that from the record!", chance = 40 },
		hurt = { "Noted.", "That is hearsay!", chance = 25 },
		death = { "The court... adjourns.", chance = 70 },
		victory = { "Case closed.", chance = 60 },
	},
}
