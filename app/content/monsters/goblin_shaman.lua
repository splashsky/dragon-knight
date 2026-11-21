-- app/content/monsters/goblin_shaman.lua :: an example monster (new in 2.2) that casts
-- spells, drinks potions and carries a weapon. It doesn't roam (roams = false): random
-- encounters never pick it; content (or an admin, with "Roams") puts it in the game.
--
-- Each turn it picks by weight among its attack (attack_weight) and the spells and items
-- it may use now: a spell it has the MP for, an item it still has (stock: per encounter),
-- whose `when` passes and whose can_cast / can_use doesn't refuse.

-- free-standing condition: m is the monster as its AI sees it (m.hp, m.maxhp, m.mp, ...)
local function low_hp(m)
	return m.hp < m.maxhp // 3
end

return {
	name = "Goblin Shaman",
	description = "Hurls Hurt spells, heals itself when wounded and carries two potions.",
	level = 5,
	maxhp = 40, maxdam = 8, armor = 4,
	maxexp = 12, maxgold = 15,
	immune = 0,
	maxmp = 17,                         -- the Mage's MP at level 5
	roams = false,
	attack_weight = 3,
	equipment = { weapon = "dagger" },  -- its attack adds to the damage: maxdam 8 + 8
	spells = {
		{ spell = "hurt", weight = 2 },
		-- inline condition
		{ spell = "heal", weight = 3, when = function(m) return m.hp < m.maxhp // 2 end },
	},
	items = {
		{ item = "potion", weight = 4, stock = 2, when = low_hp },
	},
	-- what it says in a fight (fight/speech.lua, docs/APP.md "Monster speech"): at each
	-- moment it may speak (`chance`, a percent: never for certain; `once = true` on a list:
	-- once a fight), then a line is picked by weight (1 unless given) among those that may
	-- be said now: `when` is a condition (statuses it or the player has or lacks, shares of
	-- HP, the round, or a function(m) like the spells' `when`); `once = true` a line said
	-- once a fight, `once = "condition"` once each time its `when` comes true. "{player}" is
	-- the player's name. At most one line a round, but for its last.
	speech = {
		start = { "Shiny things! Give me your shiny things!", "Spirits, look! Supper walks to us!", chance = 60 },
		turn = {
			"Hee hee hee!", "The spirits are watching you.",
			-- while the player sleeps: likelier than the others (weight 3)
			{ text = "Sleepy, sleepy! The spirits tickle your toes!", weight = 3, when = { foe_has = { "sleep" } } },
			chance = 20,
		},
		winning = { "You bleed so nicely. Bleed some more!", { text = "The spirits laugh at you, {player}!", weight = 2 }, chance = 30 },
		losing = {
			"No fair! No fair!", "I was only borrowing the road...",
			-- once a fight, and only when badly hurt
			{ text = "Spirits! Spirits, help! Anyone?", once = true, when = { hp_below = 25 } },
			chance = 35,
		},
		hurt = { "Ow! Ow! Ow!", "That one... I will remember that one.", chance = 25 },
		healed = { "The spirits mend me!", chance = 50 },
		status = {
			sleep = { "Zzz... shiny...", chance = 60 },
			poison = {
				"Bad juice! I taste bad juice!",
				-- poisoned while asleep: two statuses at once
				{ text = "Bad juice AND bad dreams... not fair...", weight = 3, when = { has = { "poison", "sleep" } } },
				chance = 70,
			},
		},
		death = { "Spirits... take me...", "Not... the... shinies...", chance = 70 },
		victory = { "Shinies for me! All the shinies!", "The spirits eat well tonight.", chance = 80 },
	},
}
