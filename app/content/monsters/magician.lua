-- app/content/monsters/magician.lua :: the Magician (the original game's monster 21).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function wounded(m)
	return m.hp < m.maxhp // 2
end

local function unburnt(m)
	return not m.target:has_status("burning")
end

return {
	name = "Magician",
	lore = [[
A robed caster who learned his tricks in a tower near Gilead and was thrown out for
practising on the students. He is quick with a spell, and his fire is more dangerous than
the sword he carries. The Gilead guards would like a word with him, but they have not yet
found the nerve to try.]],
	icon = "magician",
	level = 8,
	maxhp = 30, maxdam = 24, armor = 10,
	maxexp = 36, maxgold = 12,
	class = "mage",
	maxmp = 30,
	attack_weight = 2,
	spells = {
		-- sets you alight, once the last fire is out
		{ spell = "ember", weight = 4, when = unburnt },
		-- hurls a Hurt
		{ spell = "hurt", weight = 2 },
		-- a small bolt of lightning
		{ spell = "spark", weight = 1 },
		-- puts you to sleep unless you already are
		{ spell = "sleep", weight = 1, when = awake },
		-- heals itself under half HP
		{ spell = "heal", weight = 3, when = wounded },
		-- Magic Bolt when its MP runs low
		{ spell = "magic_bolt", weight = 1, when = function(m) return m.mp < 10 end },
	},
	speech = {
		start = { "A student, is it? Pay attention.", chance = 35 },
		turn = { "Gilead taught you nothing, {player}.", "Watch the hands, not the words.", chance = 20 },
		hurt = { "Clumsy! You will pay for that.", chance = 25 },
		losing = { "This is not over. Remember my name.", chance = 25 },
		death = { "Gilead... will hear of this...", chance = 40 },
		victory = { "Another lesson learned, {player}.", chance = 30 },
	},
}
