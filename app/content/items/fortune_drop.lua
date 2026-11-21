-- app/content/items/fortune_drop.lua :: Fortune Drop, a monster drop (the original game's drop 32).
return {
	name = "Fortune Drop",
	lore = [[
A flat copper coin with a hole punched through it, dropped by cutpurses on the roads near
Midworld. Gamblers in every town carry one on a string for luck. Nobody can say whether they
work, but the thieves who carried them never went hungry.]],
	category = "accessory",
	drop_level = 5,
	modifiers = { { kind = "stat", stat = "gold_bonus_pct", amount = 10 } },
}
