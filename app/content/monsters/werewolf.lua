-- app/content/monsters/werewolf.lua :: the Werewolf (the original game's monster 51).
local function wounded(m)
	return m.hp < m.maxhp // 2
end

local function unraged(m)
	return not m:has_status("uber_damage")
end

local function unmended(m)
	return not m:has_status("regen")
end

return {
	name = "Werewolf",
	lore = [[
A man who was bitten and has not yet stopped being a man entirely. Werewolves wait at the
edge of villages on the nights of the full moon, and the farmers around Kalle bar their
doors and keep the dogs in. They still understand speech and enjoy using it to mock the
hunters who come looking. Silver is the only thing that reliably ends one, which is why
the smiths charge double for it.]],
	icon = "werewolf",
	level = 17,
	maxhp = 56, maxdam = 48, armor = 38,
	maxexp = 124, maxgold = 41,
	resist = { holy = -50 },                    -- silver, in the old tongue
	ward = { poison = 25 },
	maxmp = 57,
	spells = {
		-- rages at night, or by day once it is under half HP
		{ spell = "rage", weight = 6, when = function(m)
			return unraged(m) and (m:has_field("night") or wounded(m))
		end },
		-- knits itself under half HP (Grit refuses above it)
		{ spell = "grit", weight = 3, when = unmended },
	},
	speech = {
		start = { "Run, little hunter. Run.", chance = 40 },
		turn = { "*howls*", "Your fear is sweet, {player}.", chance = 15 },
		winning = { "Do you smell that, {player}? That is your fear.", chance = 30 },
		hurt = { "Argh! That stung.", chance = 30 },
		death = { "The moon... takes me back...", chance = 60 },
		victory = { "Good hunting tonight.", chance = 50 },
	},
}
