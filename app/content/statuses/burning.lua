-- app/content/statuses/burning.lua :: a fire on the bearer that burns it for a fixed amount
-- on every tick of the clock (the Ember spell: s.target:afflict("burning", { ticks = n,
-- amount = m })). Unlike poison the damage doesn't vary. Fire damage.
return {
	name = "Burning",
	description = "Takes fire damage every 10 seconds.",
	lore = [[
Fire caught on the clothes or the skin, from an Ember or a torch that came too close. It
does the same damage each turn and doesn't ease off, so it is over when it has burned
itself out. Rolling on the ground helps. Mages who cast fire at close range learn to
carry a wet cloak.]],
	icon = "burning",
	kind = "harmful",
	ticks = 3,
	data = { amount = 7 },
	messages = {
		hurt = "The %s burns for %d damage.",
		hurt_you = "You burn for %d damage.",
	},
	on_tick = function(t)
		local dealt = t.bearer:hurt(t.data.amount, "fire")
		if t.bearer.is_player then t:say("hurt_you", dealt) else t:say("hurt", t.bearer.name, dealt) end
	end,
}
