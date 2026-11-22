-- app/content/monsters/warlock.lua :: the Warlock (the original game's monster 42).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function unwarded(m)
	return not m:has_status("uber_defense")
end

local function unweakened(m)
	return not m.target:has_status("weakened")
end

return {
	name = "Warlock",
	lore = [[
A caster who traded a piece of his soul for a stronger spellbook, and now has to keep trading.
Warlocks sell charms and curses from the back rooms of the towns, and they will sell you one if you
ask nicely. Most of them are polite until they are not.]],
	icon = "warlock",
	level = 15,
	maxhp = 48, maxdam = 40, armor = 26,
	maxexp = 100, maxgold = 33,
	resist = { arcane = 100, shadow = 50, holy = -25 },   -- no hurt spells
	ward = { sleep = 25 },
	class = "mage",
	maxmp = 52,
	attack_weight = 2,
	spells = {
		-- wards himself in his first two turns
		{ spell = "ward", weight = 6, when = function(m) return m.turn <= 2 and unwarded(m) end },
		-- weakens you, once
		{ spell = "enfeeble", weight = 3, when = unweakened },
		-- aches you with Pain
		{ spell = "pain", weight = 3 },
		-- hurls a Hurt
		{ spell = "hurt", weight = 1 },
		-- a small bolt of lightning
		{ spell = "spark", weight = 1 },
		-- puts you to sleep unless you already are
		{ spell = "sleep", weight = 1, when = awake },
		-- heals itself under 40% HP
		{ spell = "heal", weight = 4, when = function(m) return m.hp < m.maxhp * 4 // 10 end },
		-- revives itself a little under 40% HP
		{ spell = "revive", weight = 2, when = function(m) return m.hp < m.maxhp * 4 // 10 end },
		-- Magic Bolt when its MP runs low
		{ spell = "magic_bolt", weight = 1, when = function(m) return m.mp < 10 end },
	},
	speech = {
		start = { "Pleasant of you to come. Shall we make a deal?", chance = 50 },
		turn = { "Every bargain has a price, {player}.", "Your contract is so interesting.", chance = 25 },
		winning = { "Paid in full, {player}.", chance = 30 },
		losing = { "That is not in the terms!", chance = 35 },
		hurt = { "You will regret breaking my charm.", chance = 25 },
		status = {
			sleep = { "Sleep now. The price can wait.", chance = 40 },
		},
		death = { "The contract... void...", chance = 60 },
		victory = { "A fine bargain for me.", chance = 60 },
	},
}
