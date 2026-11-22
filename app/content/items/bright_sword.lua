-- app/content/items/bright_sword.lua :: the Bright Sword (the original game's item 14).
return {
	name = "Bright Sword",
	lore = [[
A long blade of pale steel that still catches the light in a cellar, made by smiths who
will not say what they quench it in. Warriors who carry one swear it sings in the hand,
and that they learn more from each hard fight with it at their side. Only a few shops in
the far towns stock them, and they never stay on the rack long.]],
	icon = "bright_sword",
	category = "weapon",
	price = 6000,
	attack = 100,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = 10 } },
}
