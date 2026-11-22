-- app/content/items/travel_tea.lua :: restores travel points (TP), usable in town.
return {
	name = "Travel Tea",
	description = "Restores 30 travel points. Drink it in town, before the road.",
	lore = [[
A pale tea of mint and bark, brewed in a tin pot at the market stalls and poured into
whatever cup the traveller brings. The road tiredness it chases is the kind a long walk
leaves in the legs. Carters swear by it, and an innkeeper in Bris once told a customer
that it was the only thing he had ever sold that people came back for.]],
	icon = "travel_tea",
	category = "consumable",
	price = 25,
	max_stack = 10,
	usable_in = "town",
	target = "self",
	power = 30,                     -- the most TP it restores
	messages = {
		used = "You have drunk the %s, and gained %d Travel Points.",
		full = "Your Travel Points are already full. Please go back and try again.",
		full_town = "Your Travel Points are already full. You don't need to drink the %s now.",
	},
	can_use = function(u)
		if u.caster.tp >= u.caster.maxtp then return u:refuse("full_town", u.name) end
	end,
	use = function(u)
		u:say("used", u.name, u.caster:heal("tp", u.power))
	end,
}
