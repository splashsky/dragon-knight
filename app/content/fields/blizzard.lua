-- app/content/fields/blizzard.lua :: a blizzard (the weather's sky "blizzard", a storm's core in
-- the north): frost strong, no fire can catch, sleep deeper, everyone half frozen.
return {
	name = "Blizzard",
	description = "A howling blizzard: frost is strong, fire weak and unable to catch, sleep comes deeper, and everyone is slowed.",
	icon = "blizzard",
	group = "sky",
	damage = { frost = 30, fire = -30, wind = 15 },
	statuses = {
		burning = { blocked = true },
		sleep = { scale = { chance = 120 } },
	},
	stats = { dexterity = -20 },
	messages = {
		begins = "A blizzard sweeps over the field.",
		ends = "The blizzard blows itself out.",
		blocked = "The driving snow smothers the fire before it can catch.",
	},
}
