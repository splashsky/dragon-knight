-- app/content/items/bearclaw_totem.lua :: Bearclaw Totem, a single-use charm that casts Warlord (a monster drop).
return {
	name = "Bearclaw Totem",
	description = "A bear's claw strung on a leather cord, with a carved face. Equipped, it casts " ..
		"Warlord in a fight twice, and is used up by the second cast. An inn does not recharge it.",
	lore = [[
A bear that has taken a chieftain's life in the mountains above Endworld is skinned, and its
claws are taken to the grave-mound of the clan. Those that fall from the living bears are
hung on a cord by whoever finds them and carried into battle. The clan's old women say the
bear's roar is still in the claw, and that it will give a warrior one good shout before it goes
quiet for good.]],
	icon = "bearclaw_totem",
	category = "accessory",
	drop_level = 45,
	casts = "warlord",
	charges = 2,
	rechargeable = false,
}
