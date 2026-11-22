-- app/content/monsters/siren.lua :: the Siren (the original game's monster 60).
return {
	name = "Siren",
	lore = [[
The Siren sings from the rocks of the sea-coast beyond Endworld, and sailors who hear her row
toward the sound. She is immune to hurt and sleep spells, so the fight is fought with steel. Her
song is never quite the same twice. Those who survive say she only ever sang one verse, and it
was about them.
]],
	icon = "siren",
	level = 50,
	maxhp = 68, maxdam = 400, armor = 800,
	maxexp = 10000, maxgold = 50,
	resist = { arcane = 100 }, ward = { sleep = 100 },  -- immune to arcane (the hurt spells) and to sleep
	maxmp = 186,
	speech = {
		start = { "Come closer, {player}. The rocks are very sharp.", "Listen. I know what you want to hear.", chance = 65 },
		turn = { "Your oars have stopped, sailor.", "Hush now. The verse is nearly done.", chance = 15 },
		winning = { "The sea always keeps its promises.", chance = 35 },
		losing = { "You row against my song? Foolish.", chance = 45 },
		hurt = { "Oh! Rude.", chance = 20 },
		death = { "The last verse... was yours...", chance = 80 },
		victory = { "Another one for the rocks.", chance = 85 },
	},
}
