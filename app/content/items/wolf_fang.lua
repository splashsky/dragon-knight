-- app/content/items/wolf_fang.lua :: Wolf Fang, a monster drop.
return {
	name = "Wolf Fang",
	lore = [[
A yellowed canine from a grey wolf that came down out of the hills and took three sheep
before it was killed. Farmers on the Midworld road string them on leather and hang them
by the door. The hunters who sell them say a fang worn on the hand makes a better club
grip than any wood.]],
	icon = "wolf_fang",
	category = "accessory",
	drop_level = 4,
	modifiers = { { kind = "stat", stat = "attack", amount = 10 } },
}
