-- app/content/monsters/traitor.lua :: the Traitor (the original game's monster 132).
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

-- lights the keg from its third turn on, when you could take three times its blast (40% of its attack)
local function lights(m)
	local b = barrel(m)
	return m.turn >= 3 and b and not b:has_status("fuse") and not wet(m)
		and m.target.hp > m.attack * 12 // 10
end

return {
	name = "Traitor",
	lore = [[
The Traitor was once a captain of the Hambry garrison who sold the gate keys to the raiders
for a share of the take. He now serves whoever pays him, and he is loyal to no one who has
not paid him yet. He is not a monster, only a man who found the price of honour too high.
He will sell the next gate too.
]],
	icon = "traitor",
	level = 45,
	maxhp = 230, maxdam = 205, armor = 175,
	maxexp = 1150, maxgold = 383,
	ward = { weakened = 25 },
	maxmp = 167,
	attack_weight = 6,
	items = {
		-- "I was told you would come": he comes prepared, and throws weakening dust...
		{ item = "weakening_dust", weight = 5, stock = 2, when = function(m) return not m.target:has_status("weakened") end },
		-- ...and acid
		{ item = "acid_vial", weight = 4, stock = 2 },
		-- and he can be bought off a potion under a third of his life
		{ item = "potion", weight = 8, stock = 2, when = function(m) return m.hp < m.maxhp // 3 end },
		-- rolls a keg of blasting powder onto the field on his second turn (now and then)
		{ item = "explosive_barrel", weight = 3, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from his third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	speech = {
		start = { "Ah, {player}. I was told you would come.", "Who is paying you to stand there?", chance = 60 },
		turn = {
			"I could be persuaded to switch sides, you know.", "Every gate has a price.",
			{ text = "A gift from the garrison stores. Do not touch it.", weight = 4, when = rolls_out },
			{ text = "The price of the gate, {player}. Paid in fire.", weight = 4, when = lights },
			chance = 15,
		},
		winning = { "Loyalty is a poor purse, friend.", chance = 35 },
		losing = { "Wait, wait. We can still make a deal.", chance = 45 },
		hurt = { "That was not in the bargain!", chance = 20 },
		death = { "I sold them all... and still lost...", chance = 75 },
		victory = { "Sold, and paid. Pleasure doing business.", chance = 80 },
	},
}
