-- app/content/items/acid_vial.lua :: a thrown vial of acid: hurts the monster outright
-- (armor does not stop it). Fights only; immune monsters are not hurt.
return {
	name = "Acid Vial",
	description = "Throws acid that hurts the monster for a fixed amount, whatever its armor. Some monsters are immune.",
	lore = [[
A thick green acid in a glass vial that cracks when it lands, sold by a chemist in Bris
who wears gloves to the market and will not say where the acid comes from. It eats
through armor plate in a few breaths, and a hunter who has been splashed will tell you it
smells of wet pennies. Sailors buy it for barnacles, and a few of them use it on other
things.]],
	icon = "acid_vial",
	category = "consumable",
	price = 120,
	max_stack = 10,
	usable_in = "fight",
	power = 45,                     -- the damage it does
	messages = {
		used = "You throw the %s for %d damage.",
		immune = "You throw the %s, but the monster is immune to it.",
	},
	can_use = function(u)
		if u.target.immune ~= 0 then return u:refuse("immune", u.name) end
	end,
	use = function(u)
		u.target:hurt(u.power)
		u:say("used", u.name, u.power)
	end,
}
