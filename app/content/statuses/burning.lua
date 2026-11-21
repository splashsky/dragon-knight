-- app/content/statuses/burning.lua :: a fire on the bearer that burns it for a fixed amount
-- at the end of each of its turns (the Ember spell: s.target:afflict("burning", { turns = n,
-- amount = m })). Unlike poison the damage doesn't vary.
return {
	name = "Burning",
	description = "Takes fire damage at the end of every turn.",
	kind = "harmful",
	tick_on = "turn_end",
	turns = 3,
	data = { amount = 7 },
	messages = {
		hurt = "The %s burns for %d damage.",
		hurt_you = "You burn for %d damage.",
	},
	on_tick = function(t)
		t.bearer:hurt(t.data.amount)
		if t.bearer.is_player then t:say("hurt_you", t.data.amount) else t:say("hurt", t.bearer.name, t.data.amount) end
	end,
}
