-- app/content/items/destiny_raiment.lua :: the Destiny Raiment (the original game's item 27).
return {
	name = "Destiny Raiment",
	lore = [[
The robe of the Destiny set, cut from grey silk that shifts colour in the light. Tailors
who have worked on it will not say where the cloth came from, only that it was woven for
someone else first. It is light, it turns blows well, and its wearer moves quicker than
before.]],
	icon = "destiny_raiment",
	category = "armor",
	price = 50000,
	defense = 200,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 50 } },
}
