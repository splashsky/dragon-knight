-- app/content/fields/blizzard.lua :: a blizzard (the weather's sky "blizzard", a storm's core in
-- the north): frost strong, no fire can catch, sleep deeper, everyone half frozen.
return {
	name = "Blizzard",
	description = "A howling blizzard: frost is strong, fire weak and unable to catch, sleep comes deeper, and everyone is slowed.",
	lore = [[
Blizzards come down out of the north in the cold months, and Gilead gets the worst of
them. The snow drives sideways and no torch stays lit in it, so the Mages of Hambry do
not bother with fire here. Travellers who sit down in a drift to rest often do not get
up, and the Hambry guards ring a bell at the gate on bad nights so the lost can find the
road.]],
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
