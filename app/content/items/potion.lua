-- app/content/items/potion.lua :: a healing potion (new in 2.1).
local function can_use(u)
	if u.caster.hp >= u.caster.maxhp then return u:refuse(u.in_fight and "full" or "full_town", u.name) end
end

local function use(u)
	u:say("used", u.name, u.caster:heal("hp", u.power))
end

return {
	name = "Potion",
	description = "Restores 100 hit points, in a fight or out of it.",
	lore = [[
A red healing draught in a stoppered glass bottle, the most common remedy on the road.
Apothecaries in every town brew it, and the good ones seal the cork with wax. It tastes
sour and works quickly.]],
	category = "consumable",
	price = 60,
	max_stack = 10,
	icon = "potion",                -- public/images/items/potion.png
	usable_in = "both",
	target = "self",
	power = 100,                    -- the most HP it restores
	messages = {
		used = "You have used the %s, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use the %s now.",
	},
	can_use = can_use,
	use = use,
}
