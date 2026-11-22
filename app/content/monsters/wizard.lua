-- app/content/monsters/wizard.lua :: the Wizard (the original game's monster 58).
return {
	name = "Wizard",
	lore = [[
A wizard in these hills is usually a mage who lost a bet, a debt or a lover and took to the
wild. They camp in ruined towers past Narcissa and pay for their keep with minor curses on
passing traders. Wizards are frail, but their spells can strip a warrior's armour before
the sword is even drawn. Mages in Midworld will tell you these are no true mages at all,
which the wizards take poorly.]],
	icon = "wizard",
	level = 20,
	maxhp = 66, maxdam = 56, armor = 44,
	maxexp = 144, maxgold = 48,
	immune = 0,
	maxmp = 70,
	speech = {
		start = { "Another fool on my road. How quaint.", chance = 50 },
		turn = { "Mm. Interesting.", chance = 15 },
		winning = { "Your armour is mine, {player}.", chance = 30 },
		hurt = { "Impudent!", chance = 30 },
		losing = { "Hmph. Mere luck.", chance = 40 },
		death = { "My notes... someone burn my notes...", chance = 60 },
		victory = { "A fine addition to my collection.", chance = 50 },
	},
}
