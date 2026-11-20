-- app/content/items/herb.lua :: a healing herb (new in 2.1). Consumables stack in the bag
-- (max_stack) and are scripted like spells (docs/APP.md "Scripting spells and items"):
-- power and the message strings are data, can_use and use the behaviour (inline here;
-- potion.lua uses free-standing functions). Usable in town or in a fight.
return {
	name = "Herb",
	description = "Restores 30 hit points, in a fight or out of it.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
A bitter green leaf that grows wild along the roads around Midworld. Travelers chew it on
the march, and every shopkeeper sells it by the bundle for a few pieces of gold. It tastes
terrible and works every time.]],
	category = "consumable",
	price = 15,
	max_stack = 10,
	usable_in = "both",
	target = "self",
	power = 30,                     -- the most HP it restores
	messages = {
		used = "You have used the %s, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use the %s now.",
	},
	can_use = function(u)
		if u.caster.hp >= u.caster.maxhp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
	end,
	use = function(u)
		u:say("used", u.name, u.caster:heal("hp", u.power))
	end,
}
