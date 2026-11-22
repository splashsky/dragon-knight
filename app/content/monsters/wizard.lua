-- app/content/monsters/wizard.lua :: the Wizard (the original game's monster 58).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function guarded(m)
	return m:has_status("uber_defense")
end

local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

return {
	name = "Wizard",
	lore = [[
A wizard in these hills is usually a mage who lost a bet, a debt or a lover and took to the
wild. They camp in ruined towers past Narcissa and pay for their keep with minor curses on
passing traders. Wizards are frail, but their spells can strip a warrior's armour before
the sword is even drawn. Mages in Midworld will tell you these are no true mages at all,
which the wizards take poorly.]],
	icon = "wizard",
	level = 20,
	maxhp = 66, maxdam = 56, armor = 44,
	maxexp = 144, maxgold = 48,
	class = "mage",
	maxmp = 70,
	attack_weight = 4,                  -- the class adds hurt, spark, pain and frostbite at weight 1
	spells = {
		-- strips your damage first (Enfeeble)
		{ spell = "enfeeble", weight = 4,
			when = function(m) return not m.target:has_status("weakened") end },
		-- wards itself
		{ spell = "ward", weight = 3, when = function(m) return not guarded(m) end },
		-- heals itself under half HP
		{ spell = "heal", weight = 4, when = function(m) return m.hp < m.maxhp // 2 end },
		-- lights you with Ember (not in the rain)
		{ spell = "ember", weight = 1,
			when = function(m) return not m.target:has_status("burning") and not wet(m) end },
		-- puts you to sleep
		{ spell = "sleep", weight = 1, when = awake },
		-- not used: the Mage's other spells (no Dream, Magic Bolt, Revive or rain)
		{ spell = "dream", weight = 0 },
		{ spell = "magic_bolt", weight = 0 },
		{ spell = "revive", weight = 0 },
		{ spell = "rain_call", weight = 0 },
	},
	items = {
		-- drinks one Ether when its magic runs dry
		{ item = "ether", weight = 4, stock = 1, when = function(m) return m.mp < 15 end },
	},
	speech = {
		start = { "Another fool on my road. How quaint.", chance = 50 },
		turn = { "Mm. Interesting.", { text = "Rain. How tiresome.", when = wet }, chance = 15 },
		winning = { "Your armour is mine, {player}.", chance = 30 },
		hurt = { "Impudent!", chance = 30 },
		losing = { "Hmph. Mere luck.", chance = 40 },
		death = { "My notes... someone burn my notes...", chance = 60 },
		victory = { "A fine addition to my collection.", chance = 50 },
	},
}
