-- app/content/fields/thunderstorm.lua :: a thunderstorm (the weather's sky "thunderstorm", at
-- the core of a storm; a Storm Call spell): lightning strong, no fire can catch, and now and
-- then a bolt strikes someone in the fight.
local function strike(e)
	if e:roll(1, e.data.chance) ~= 1 then return end
	local who = e.combatants[e:roll(1, #e.combatants)]
	local dealt = who:hurt(e:roll(e.data.min, e.data.max), "lightning")
	if who.is_player then e:say("strike_you", dealt) else e:say("strike", who.name, dealt) end
end

return {
	name = "Thunderstorm",
	description = "Thunder and lashing rain: lightning is strong, fire weak and unable to catch, and bolts strike at random.",
	lore = [[
Storms form near Midworld and drift north-west toward Gilead in about two hours. The
thunderstorm is the heart of one, where the lightning comes often enough to be counted.
A bolt picks its target at random, friend or foe, so the wise stand at the edge of the
fight and let the storm pass. Mages who call one with Storm Call say it is the only
spell that asks them for a little luck.]],
	icon = "thunderstorm",
	group = "sky",
	damage = { lightning = 30, fire = -25, wind = 15 },
	statuses = {
		burning = { blocked = true },
	},
	data = { chance = 6, min = 3, max = 8 },   -- a bolt 1 in `chance` ticks, min-max lightning damage
	messages = {
		begins = "Thunder cracks overhead as a storm breaks over the field.",
		ends = "The thunder rolls away.",
		blocked = "The rain puts the fire out before it can catch.",
		strike = "Lightning strikes the %s for %d damage!",
		strike_you = "Lightning strikes you for %d damage!",
	},
	on_tick = strike,
}
