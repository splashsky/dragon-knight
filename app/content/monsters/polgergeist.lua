-- app/content/monsters/polgergeist.lua :: the Polgergeist (the original game's monster 71).
return {
	name = "Polgergeist",
	lore = [[
A Polgergeist is the restless spirit of someone who died angry and was never buried
properly. It throws things: dishes, stones, sometimes the furniture of whoever is
sleeping in its house. Innkeepers on the road out of Kalle pay a priest to walk the
rooms with salt before they will let a bed go out for the night.
]],
	icon = "polgergeist",
	level = 25,
	maxhp = 84, maxdam = 74, armor = 58,
	maxexp = 180, maxgold = 60,
	resist = { neutral = 25, shadow = 50, poison = 100, holy = -50 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	maxmp = 91,
	attack_weight = 2,
	spells = {
		-- throws things: Hurt, Pain or a plain blow, no telling which
		{ spell = "hurt", weight = 2 },
		-- throws Pain
		{ spell = "pain", weight = 2 },
	},
	speech = {
		start = { "Get OUT of my house!", chance = 45 },
		turn = { "*crash*", "Who put that there?", chance = 25 },
		winning = { "Ha! Sleep in the cellar, {player}.", chance = 30 },
		losing = { "It was my house first...", chance = 35 },
		hurt = { "*shrieks*", "You hit like my brother did.", chance = 20 },
		death = { "At last... I can rest...", chance = 60 },
		victory = { "Ahh, the bed is mine again.", chance = 55 },
	},
}
