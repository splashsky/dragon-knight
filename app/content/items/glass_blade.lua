-- app/content/items/glass_blade.lua :: the Glass Blade (a sword of cast, unannealed glass).
return {
	name = "Glass Blade",
	description = "A very sharp sword that hits hard, but it takes a toll on the wielder's Maximum Hit Points while equipped.",
	lore = [[
Gilead's glassmiths cast a blade from clear, unannealed glass and sell it with a warning
on the box. The edge will split a shield and a mail sleeve in one stroke, and it will not
last a week in the hands of a careless man. A wielder who keeps it in a fight finds that
he has less blood to lose, which is the sort of thing that makes a buyer read the label
twice.]],
	icon = "glass_blade",
	category = "weapon",
	price = 9000,
	attack = 190,
	modifiers = { { kind = "stat", stat = "maxhp", amount = -80 } },
}
