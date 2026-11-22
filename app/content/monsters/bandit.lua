-- app/content/monsters/bandit.lua :: the Bandit (the original game's monster 47).
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
		-- rolls a keg of blasting powder onto the field on its second turn
		{ item = "explosive_barrel", weight = 5, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from its third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	speech = {
		start = { "Stand and deliver! Hand it over!", chance = 50 },
		turn = {
			"Don't make us do this the hard way.", "Keep your hands where I can see them.",
			{ text = "Roll it over here, lads. Gently.", weight = 4, when = rolls_out },
			{ text = "Stand clear, lads. Light the rag.", weight = 4, when = lights },
			chance = 25,
		},
		winning = { "Easy, that was. Easy.", chance = 30 },
		losing = { "Run! Run for the rocks!", chance = 40 },
		hurt = { "Ow! That's my good cloak!", chance = 30 },
		death = { "Tell Ned I... never mind.", chance = 60 },
		victory = { "That's the wagon, lads!", chance = 50 },
	},
}
