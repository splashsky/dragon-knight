-- app/content/monsters/sorceror.lua :: the Sorceror (the original game's monster 33).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function unweakened(m)
	return not m.target:has_status("weakened")
end

return {
	name = "Sorceror",
	lore = [[
A caster who learned enough magic to be dangerous and not enough to be careful. Sorcerors take
apprentices, quarrel with them, and then forget why. They are common in the towns past Bris,
where the libraries are cheap and nobody checks the guild lists. Keep your distance, since
their spells carry farther than their manners.]],
	icon = "sorceror",
	level = 11,
	maxhp = 41, maxdam = 33, armor = 22,
	maxexp = 68, maxgold = 23,
	ward = { sleep = 25 },
	class = "mage",
	maxmp = 38,
	attack_weight = 2,
	spells = {
		-- hurls a Hurt
		{ spell = "hurt", weight = 3 },
		-- a small bolt of lightning
		{ spell = "spark", weight = 2 },
		-- puts you to sleep unless you already are
		{ spell = "sleep", weight = 1, when = awake },
		-- weakens you, once
		{ spell = "enfeeble", weight = 2, when = unweakened },
		-- heals itself under 40% HP
		{ spell = "heal", weight = 4, when = function(m) return m.hp < m.maxhp * 4 // 10 end },
		-- revives itself a little under 40% HP
		{ spell = "revive", weight = 2, when = function(m) return m.hp < m.maxhp * 4 // 10 end },
		-- Magic Bolt when its MP runs low
		{ spell = "magic_bolt", weight = 1, when = function(m) return m.mp < 10 end },
	},
	items = {
		-- drinks an Ether when it runs dry: a second wind
		{ item = "ether", weight = 4, stock = 1, when = function(m) return m.mp < 10 end },
	},
	speech = {
		start = { "Ah, a student! Stand still while I test you.", chance = 50 },
		turn = { "Watch closely, this is the important part.", "Your spellbook is wrong, you know.", chance = 25 },
		winning = { "Class dismissed, {player}.", chance = 30 },
		losing = { "That spell was ALMOST right!", chance = 35 },
		hurt = { "You will pay for the notes you spoiled!", chance = 25 },
		status = {
			sleep = { "Do not nap during my lecture!", chance = 40 },
		},
		death = { "My notes... someone burn my notes...", chance = 60 },
		victory = { "Another failed pupil.", chance = 60 },
	},
}
