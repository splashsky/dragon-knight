-- app/content/statuses/doom.lua :: a death sentence (the Doom spell: s.target:afflict("doom",
-- { ticks = n, damage = m })). It counts its ticks down, and only when they run out
-- (on_expire: not when it is cured, replaced or the fight ends) the bearer takes `damage`
-- of shadow damage. A cure for harmful statuses (Cleanse, Mend, Antidote, Cure-All) lifts it.
return {
	name = "Doom",
	description = "When its time runs out, the bearer takes heavy shadow damage. Any cure for harmful effects lifts it.",
	icon = "doom",
	kind = "harmful",
	ticks = 4,
	data = { damage = 20 },
	messages = {
		fell = "The doom falls on the %s for %d damage.",
		fell_you = "The doom falls on you for %d damage!",
	},
	on_expire = function(t)
		local dealt = t.bearer:hurt(t.data.damage, "shadow")
		if t.bearer.is_player then t:say("fell_you", dealt) else t:say("fell", t.bearer.name, dealt) end
	end,
}
