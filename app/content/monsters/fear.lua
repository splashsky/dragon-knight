-- app/content/monsters/fear.lua :: the Fear (the original game's monster 66).
local function awake(m)
	return not m.target:has_status("sleep")
end

return {
	name = "Fear",
	lore = [[
Fear is not a monster in the usual sense, but the cold that gathers in the mind of a
traveller on the road to Endworld. It takes no shape until it is close, and then it wears
whatever the hero is most afraid of. A steady hand and a good night's sleep keep it at
bay. Several soldiers from Gilead have been found sitting by the road, unharmed and unable
to say why they stopped.]],
	icon = "fear",
	level = 23,
	maxhp = 76, maxdam = 66, armor = 52,
	maxexp = 165, maxgold = 55,
	resist = { neutral = 25, shadow = 50, poison = 100, holy = -25 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	maxmp = 82,
	spells = {
		-- weakens you (Enfeeble)
		{ spell = "enfeeble", weight = 3,
			when = function(m) return not m.target:has_status("weakened") end },
		-- puts the weak to sleep: only once you are under half HP
		{ spell = "dream", weight = 2,
			when = function(m) return awake(m) and m.target.hp < m.target.maxhp // 2 end },
	},
	speech = {
		start = { "You know what I am.", chance = 40 },
		turn = { "Look behind you.", chance = 20 },
		winning = { "Stop running, {player}.", chance = 30 },
		hurt = { "That was not supposed to happen.", chance = 25 },
		losing = { "You are shaking, {player}.", chance = 35 },
		death = { "Fear... fades... without you.", chance = 50 },
		victory = { "Sleep well. I will wait.", chance = 40 },
	},
}
