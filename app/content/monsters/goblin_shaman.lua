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
}
