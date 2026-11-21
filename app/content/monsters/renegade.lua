-- app/content/monsters/renegade.lua :: the Renegade (the original game's monster 123).
return {
	name = "Renegade",
	lore = [[
The Renegade was a sergeant in the Endworld garrison until the pay stopped coming for four
months running. He took his squad and their weapons over the wall and now collects tolls on
the road he once guarded. He is not cruel for the sake of it, but he has done things he will
not describe, and he expects the same loyalty from his men that he no longer gives to the
crown.
]],
	level = 42,
	maxhp = 205, maxdam = 185, armor = 150,
	maxexp = 780, maxgold = 260,
	immune = 0,
	maxmp = 151,
	speech = {
		start = { "Toll or blade. Pick one.", "You are on my road now.", chance = 60 },
		turn = { "Move, or we'll move you.", "Keep your hands where I can see them.", chance = 15 },
		winning = { "The crown never paid us. Nobody will pay you either.", chance = 35 },
		losing = { "Hold! Fall back to the wall!", chance = 40 },
		hurt = { "Gods, that stung.", chance = 25 },
		death = { "Tell them... I was a soldier once.", chance = 70 },
		victory = { "Pay the toll to the dead, friend.", chance = 75 },
	},
}
