-- app/content/monsters/wyvern.lua :: the Wyvern (the original game's monster 98).
local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

local function snowy(m)
	return m:has_field("snow") or m:has_field("blizzard")
end

return {
	name = "Wyvern",
	lore = [[
A two-legged dragon kin that nests on the cliffs above the road between Bris and Kalle. It
has no fire, only a barbed tail and a bad temper, and it will hunt a cart for a whole day
to get at the horses. Carters paint their wagons with pitch, which the wyverns hate and
which does not always work.]],
	icon = "wyvern",
	level = 33,
	maxhp = 134, maxdam = 120, armor = 95,
	maxexp = 290, maxgold = 97,
	resist = { wind = 50, lightning = -25, poison = 75 },
	ward = { poison = 75, venom = 75 },
	maxmp = 118,
	attack_weight = 3,
	spells = {
		-- climbs out of reach on its 3rd, 7th, 11th... turn and plunges the next (not in rain, storm or snow)
		{ spell = "heavy_blow", weight = 60, when = function(m)
			return m.turn % 4 == 3 and not wet(m) and not snowy(m)
		end },
		-- stings with Venom
		{ spell = "venom", weight = 3, when = function(m) return not m.target:has_status("venom") end },
	},
	speech = {
		start = { "*hisses*", "Kraa!", chance = 20 },
		turn = { "Grrr...", { text = "*circles, waiting for a clear sky*", when = function(m) return wet(m) or snowy(m) end }, chance = 8 },
		winning = { "Kraa!", chance = 20 },
		losing = { "*screeches*", chance = 25 },
		hurt = { "Kraa!", "*thrashes its tail*", chance = 15 },
		death = { "*a long, falling cry*", chance = 50 },
		victory = { "*feeds*", chance = 40 },
		status = { charging = { "*climbs high, wings beating*", chance = 80 } },
	},
}
