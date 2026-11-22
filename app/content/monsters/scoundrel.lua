-- app/content/monsters/scoundrel.lua :: the Scoundrel (the original game's monster 36).
local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
		or m:has_field("blizzard") or m:has_field("shallows")
end

local function barrel(m)
	for _, o in ipairs(m.objects) do
		if o.key == "explosive_barrel" then return o end
	end
end

-- rolls a keg onto the field on its second turn, never in damp air
local function rolls_out(m)
	return m.turn == 2 and not barrel(m) and not wet(m)
end

-- lights the keg from its third turn on, when you could take twice its blast (it is 40% of its attack)
local function lights(m)
	local b = barrel(m)
	return m.turn >= 3 and b and not b:has_status("fuse") and not wet(m)
		and m.target.hp > m.attack * 8 // 10
end

local function unweakened(m)
	return not m.target:has_status("weakened")
end

return {
	name = "Scoundrel",
	lore = [[
A bandit who has given up pretending to be honest about it. He runs cons on the roads out of
Kalle, sells false maps to new arrivals, and will cheat his own partners if the chance comes.
Scoundrels are seldom brave, but they are rarely alone.]],
	icon = "scoundrel",
	level = 12,
	maxhp = 43, maxdam = 35, armor = 22,
	maxexp = 75, maxgold = 25,
	maxmp = 40,
	attack_weight = 3,
	items = {
		-- throws Weakening Dust at you, once
		{ item = "weakening_dust", weight = 3, stock = 1, when = unweakened },
		-- eats a herb under a third of its HP
		{ item = "herb", weight = 3, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
		-- rolls a keg of blasting powder onto the field on its second turn
		{ item = "explosive_barrel", weight = 5, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from its third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	speech = {
		start = { "Friend! You look like a man with money.", chance = 50 },
		turn = {
			"Fine words, fine words. Now the gold.", "Don't make me ask twice.",
			{ text = "A little something for your trouble, friend.", weight = 4, when = rolls_out },
			{ text = "Look at that, a spark. What luck.", weight = 4, when = lights },
			chance = 25,
		},
		winning = { "What a fool you are, {player}!", chance = 30 },
		losing = { "Wait, wait, let's talk about this!", chance = 40 },
		hurt = { "That's cheating!", chance = 30 },
		death = { "Did I cheat you first?", chance = 60 },
		victory = { "Honest work pays, eventually.", chance = 50 },
	},
}
