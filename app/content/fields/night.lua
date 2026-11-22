-- app/content/fields/night.lua :: night (the weather's time "night"; a Nightfall spell):
-- shadow strong, holy light weaker, sleep deeper.
return {
	name = "Night",
	description = "Darkness over the field: shadow is stronger, holy light weaker, and sleep comes deeper.",
	lore = [[
Night is the hour of the bandits, the thieves and the things that come out when the
lamps go out. A Nightfall spell brings it on at any hour, and the Paladins say the Mage
who casts it should sit up with the sick afterwards. Sleep takes hold deeper in the
dark, so a traveller who lies down by the road after dark may not wake when he means to.]],
	group = "time",
	damage = { shadow = 25, holy = -15 },
	statuses = {
		sleep = { scale = { chance = 130 } },
	},
	messages = {
		begins = "Night falls over the field.",
		ends = "The night pales.",
	},
}
