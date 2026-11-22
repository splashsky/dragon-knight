-- app/content/monsters/liche_king.lua :: the Liche King (the original game's monster 130).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Liche King",
	lore = [[
The Liche King was a lord of the old kingdom who had himself bound to a throne of bone so
his rule would outlast his heart. His court of the dead still meets in the crypts under Kalle,
where the floors are cold and every chair is full. He sends his servants out to collect the
tithe of gold from the living, and he counts every coin himself.
]],
	icon = "liche_king",
	level = 44,
	maxhp = 225, maxdam = 205, armor = 170,
	maxexp = 1050, maxgold = 350,
	resist = { shadow = 75, poison = 100, frost = 50, holy = -100 },
	ward = { poison = 100, sleep = 100, withering = 50 },
	class = "mage",
	maxmp = 159,
	attack_weight = 20,
	spells = {
		-- phase 1, the court (two thirds or more): the grave-fog aura (poison and shadow +25%, holy -25%)...
		{ spell = "miasma", weight = 30, when = function(m) return m.hp >= m.maxhp * 2 // 3 and not m:has_field("miasma") end },
		-- ...and a heavy hand
		{ spell = "maim", weight = 8, when = function(m) return m.hp >= m.maxhp * 2 // 3 end },
		-- phase 2, the crypt (under two thirds): it drains you...
		{ spell = "withering", weight = 14, when = function(m)
			return m.hp < m.maxhp * 2 // 3 and not m.target:has_status("withering")
		end },
		-- ...and rends
		{ spell = "rend", weight = 10, when = function(m) return m.hp < m.maxhp * 2 // 3 end },
		-- phase 3, the throne (under a third): it guards itself
		{ spell = "fend", weight = 14, when = function(m) return m.hp < m.maxhp // 3 and unguarded(m) end },
		-- boulders now and then
		{ spell = "rockfall", weight = 2 },
		-- housekeeping: no sleep-locks, summons or weather, no second Ward
		{ spell = "nightmare", weight = 0 },
		{ spell = "dream", weight = 0 }, { spell = "call_spirit", weight = 0 },
		{ spell = "rain_call", weight = 0 }, { spell = "sunfire", weight = 0 }, { spell = "cold_snap", weight = 0 },
		{ spell = "storm_call", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded },
	},
	items = {
		-- drinks a potion under three tenths of its life
		{ item = "potion", weight = 14, stock = 2, when = function(m) return m.hp < m.maxhp * 3 // 10 end },
	},
	speech = {
		start = { "Kneel, living one. The crypt was expecting you.", "Your tithe is overdue.", chance = 60 },
		turn = {
			"Your breath is a debt, {player}.", "Count your remaining years.",
			{ text = "The grave-fog gathers. Count what you can still see.", when = function(m) return m:has_field("miasma") end },
			chance = 15,
		},
		winning = { "The throne has room for one more.", chance = 35 },
		losing = { "Impossible. My crypt has never been breached.", chance = 45 },
		hurt = { "Fool. I cannot be hurt twice.", chance = 20 },
		death = { "My... throne... is still... mine...", chance = 75 },
		victory = { "Another name for the rolls.", chance = 80 },
	},
}
