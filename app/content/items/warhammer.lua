-- app/content/items/warhammer.lua :: the Warhammer (a heavy head on a short haft).
return {
	name = "Warhammer",
	lore = [[
A solid iron head on a short oak haft, built to dent plate and break a shield arm. The
weight is in the head, which makes it slow to bring back into guard, and a wielder who
swings it all day ends up with a sore back and a poor sense of where the next blow is
coming from. Narcissa's armourers sell them to men who have already decided to take the
hits.]],
	category = "weapon",
	price = 1800,
	attack = 70,
	modifiers = { { kind = "stat", stat = "dexterity", amount = -20 } },
}
