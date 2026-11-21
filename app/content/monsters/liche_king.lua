-- app/content/monsters/liche_king.lua :: the Liche King (the original game's monster 130).
return {
	name = "Liche King",
	lore = [[
The Liche King was a lord of the old kingdom who had himself bound to a throne of bone so
his rule would outlast his heart. His court of the dead still meets in the crypts under Kalle,
where the floors are cold and every chair is full. He sends his servants out to collect the
tithe of gold from the living, and he counts every coin himself.
]],
	level = 44,
	maxhp = 225, maxdam = 205, armor = 170,
	maxexp = 1050, maxgold = 350,
	immune = 0,
	maxmp = 159,
	speech = {
		start = { "Kneel, living one. The crypt was expecting you.", "Your tithe is overdue.", chance = 60 },
		turn = { "Your breath is a debt, {player}.", "Count your remaining years.", chance = 15 },
		winning = { "The throne has room for one more.", chance = 35 },
		losing = { "Impossible. My crypt has never been breached.", chance = 45 },
		hurt = { "Fool. I cannot be hurt twice.", chance = 20 },
		death = { "My... throne... is still... mine...", chance = 75 },
		victory = { "Another name for the rolls.", chance = 80 },
	},
}
