-- app/content/items/thornwood_thorn.lua :: Thornwood Thorn, the second piece of the Thornwood set.
return {
	name = "Thornwood Thorn",
	description = "A spine as long as a dagger, bound to the wrist. Adds attack, but costs maximum " ..
		"hit points. Worn with the rest of the Thornwood set.",
	lore = [[
The longest spines grow near the top of the thornwood, where the bears cannot reach and the
woodcutters are not willing to climb. Whoever gets one down has to bind it with wire before it
sticks to anything, and most of them cut themselves on it at least once. Those who fight with
a thorn on the wrist say it hurts a monster more than it hurts them, which is not much comfort
at the end of a long day.]],
	category = "accessory",
	drop_level = 26,
	modifiers = {
		{ kind = "stat", stat = "attack", amount = 55 },
		{ kind = "stat", stat = "maxhp", amount = -40 },
	},
}
