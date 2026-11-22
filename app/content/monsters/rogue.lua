-- app/content/monsters/rogue.lua :: the Rogue (the original game's monster 22).
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

local function unburnt(m)
	return not m.target:has_status("burning")
end

return {
	name = "Rogue",
	lore = [[
A thief who works the Hambry road, quick with a knife and quicker with a locked door. Rogues
like to strike from the shadows and leave with the coin before anyone hears a scream. The
Hambry guard posts a reward for each one brought in, which is usually the price of a good meal.]],
	icon = "rogue",
	level = 8,
	maxhp = 30, maxdam = 25, armor = 12,
	maxexp = 40, maxgold = 13,
	maxmp = 30,
	attack_weight = 3,
	items = {
		-- throws a Fire Flask while you aren't burning
		{ item = "fire_flask", weight = 2, stock = 1, when = unburnt },
		-- rolls a keg of blasting powder onto the field on its second turn
		{ item = "explosive_barrel", weight = 5, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from its third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	speech = {
		start = { "Hand over the purse, {player}.", chance = 30 },
		turn = {
			"Keep still and nobody gets hurt.", "Quiet, now.",
			{ text = "Mind the keg, {player}. Don't kick it.", weight = 4, when = rolls_out },
			{ text = "Shh. Count to three.", weight = 4, when = lights },
			chance = 20,
		},
		hurt = { "Ow! Dirty trick!", chance = 25 },
		losing = { "Fine! Keep your coin. Keep your head.", chance = 25 },
		death = { "Bad luck... bad luck...", chance = 35 },
		victory = { "Nice doing business with you, {player}.", chance = 30 },
	},
}
