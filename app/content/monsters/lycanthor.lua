-- app/content/monsters/lycanthor.lua :: the Lycanthor (the original game's monster 83).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function night(m)
	return m:has_field("night")
end

return {
	name = "Lycanthor",
	lore = [[
The Lycanthor is a lycan that has kept its wits, and that is worse. It works in packs in
the hill country past Kalle, and it has learned to set traps and to wait downwind of a
camp. Hunters who have survived one say it talks to its pack in a low voice, and that the
voice sounds like their own.
]],
	icon = "lycanthor",
	level = 28,
	maxhp = 100, maxdam = 90, armor = 70,
	maxexp = 210, maxgold = 70,
	resist = { holy = -50 },
	maxmp = 98,
	attack_weight = 3,
	spells = {
		-- marks you: its blows hit harder until it fades or is cleansed
		{ spell = "hunters_mark", weight = 5,
			when = function(m) return not m.target:has_status("marked") end },
		-- rages at night
		{ spell = "rage", weight = 3, when = function(m) return night(m) and not buffed(m) end },
	},
	speech = {
		start = { "We have been watching your fire, {player}.", chance = 40 },
		turn = { "*low growl*", "Circle left. Now.", { text = "The moon is up. Circle wide, pack.", when = night }, chance = 20 },
		winning = { "Your pack is gone. Mine is not.", chance = 30 },
		losing = { "Fall back! Fall back!", chance = 30 },
		hurt = { "*snarls*", "You will pay for that.", chance = 25 },
		death = { "Tell the moon I kept my word.", chance = 55 },
		victory = { "The pack eats well tonight.", chance = 50 },
	},
}
