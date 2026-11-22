-- app/content/monsters/bandit_captain.lua :: an example monster (new in 2.2) in full gear:
-- its equipment's attack, defense and modifiers count like a character's (maxdam 20 +
-- 45, armor 12 + 30 + 10, maxhp 120 + 25). It works itself into a frenzy once per fight
-- and eats its one herb when badly hurt. It doesn't roam (see goblin_shaman.lua).
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

local function unraged(m)
	return not m:has_status("uber_damage")
end

local function unmended(m)
	return not m:has_status("regen")
end

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
	ward = { sleep = 50 },
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
		-- works himself into a frenzy
		{ spell = "craze", weight = 1, when = unraged },
		-- raises a shield of Fend under 60% HP
		{ spell = "fend", weight = 3, when = function(m)
			return m.hp < m.maxhp * 6 // 10 and not m:has_status("uber_defense")
		end },
		-- knits itself under half HP (Grit refuses above it)
		{ spell = "grit", weight = 3, when = unmended },
	},
	items = {
		-- eats his herb under a third of his HP
		{ item = "herb", weight = 2, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
		-- rolls a keg of blasting powder onto the field on its second turn
		{ item = "explosive_barrel", weight = 5, stock = 1, when = rolls_out },
		-- throws a Fire Flask at the keg from its third turn on, unless you could not take the blast
		{ item = "fire_flask", weight = 12, stock = 1, aim = "explosive_barrel", when = lights },
	},
	speech = {
		start = { "Hold, travellers! Your purses are ours.", chance = 50 },
		turn = {
			"Keep moving, you lot. Nobody leaves.", "Eyes on the target!",
			{ text = "Bring up the powder, lads. Quietly.", weight = 4, when = rolls_out },
			{ text = "Fire in the hole!", weight = 4, when = lights },
			chance = 25,
		},
		winning = { "Pick them clean, lads!", chance = 30 },
		losing = { "Retreat? Retreat is for cowards!", chance = 35 },
		hurt = { "That's a fine blow. Fine.", chance = 30 },
		death = { "Tell the band... they owe me nothing...", chance = 60 },
		victory = { "Split it three ways. No, four.", chance = 60 },
	},
}
