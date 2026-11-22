-- app/content/items/void_flask.lua :: a thrown flask of void-glass shards: heavy damage
-- to the monster outright (arcane). Fights only; monsters immune to arcane are not hurt.
return {
	name = "Void Flask",
	description = "Throws a flask of black glass that tears the monster for a heavy amount, whatever its armor. Some monsters are immune.",
	lore = [[
A flask of black glass, blown in Gilead from sand that the miners bring up from below the
salt marsh and no one will say the name of. When it breaks, the shards seem to pull the
light off the monster and keep it. Mercenaries in Endworld pay for the flasks by weight,
and the glassblowers keep the receipts in a locked box, because they have had one blow
up in a shop.]],
	icon = "void_flask",
	category = "consumable",
	price = 1500,
	max_stack = 5,
	usable_in = "fight",
	power = 180,                    -- the damage it does
	messages = {
		used = "You throw the %s for %d damage.",
		immune = "You throw the %s, but the monster is immune to it.",
	},
	can_use = function(u)
		if u.target:immune_to("arcane") then return u:refuse("immune", u.name) end
	end,
	use = function(u)
		u:say("used", u.name, u.target:hurt(u.power, "arcane"))
	end,
}
