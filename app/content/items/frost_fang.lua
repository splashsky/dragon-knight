-- app/content/items/frost_fang.lua :: Frost Fang, a charm that casts Frostbite (a monster drop).
return {
	name = "Frost Fang",
	description = "A white fang of an ice wolf. Equipped, it casts Frostbite in a fight without " ..
		"costing MP, six charges at a time. Rest at an inn to recharge it.",
	lore = [[
Ice wolves live high on the passes past Narcissa and rarely come down to be seen. The fangs
they lose are cold to the touch even in summer, and a frozen tooth will shatter if it is
dropped on stone. Mages who wear one say the cold runs up their arm and into the spell, which
is more than they can say for their own hands.]],
	category = "accessory",
	drop_level = 24,
	casts = "frostbite",
	charges = 6,
}
