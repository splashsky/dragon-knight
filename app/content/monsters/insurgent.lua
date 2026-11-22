-- app/content/monsters/insurgent.lua :: the Insurgent (the original game's monster 135).
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
	name = "Insurgent",
	lore = [[
The Insurgent leads a band of farmers and smiths who hold the hill roads above Kalle and will
not pay the crown's road tax. He is not wicked, only tired of watching his neighbours hanged
for debt. His men carry crude spears and short bows, and they know every hidden path in the
hills better than the soldiers who chase them.
]],
	icon = "insurgent",
	level = 46,
	maxhp = 250, maxdam = 220, armor = 190,
	maxexp = 1300, maxgold = 433,
	ward = { weakened = 25 },
	maxmp = 172,
	attack_weight = 5,
	items = {
		-- throws a flask of fire when you are not burning
		{ item = "fire_flask", weight = 4, stock = 3, when = function(m) return not m.target:has_status("burning") end },
		-- a potion under a third of his life
		{ item = "potion", weight = 8, stock = 2, when = function(m) return m.hp < m.maxhp // 3 end },
		-- rolls a keg of blasting powder onto the field on his second turn (now and then)
		{ item = "explosive_barrel", weight = 3, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from his third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	spells = {
		-- "Your back is to the hill": the ambush, then a mark once the fight is on
		{ spell = "hunters_mark", weight = 3, when = function(m) return m.turn >= 2 and not m.target:has_status("marked") end },
	},
	speech = {
		start = { "Put down the crown's coin and walk on.", "We do not need your sort up here.", chance = 60 },
		turn = {
			"Watch the ridge, lads.", "Your back is to the hill, {player}.",
			{ text = "Roll the mine powder down, lads.", weight = 4, when = rolls_out },
			{ text = "Now, lads! Fire it!", weight = 4, when = lights },
			chance = 15,
		},
		winning = { "Tell the crown the hills are ours.", chance = 35 },
		losing = { "Fall back to the gully!", chance = 40 },
		hurt = { "A fair blow.", chance = 20 },
		death = { "Our fields... will still be ours.", chance = 70 },
		victory = { "The road is free for another week.", chance = 75 },
	},
}
