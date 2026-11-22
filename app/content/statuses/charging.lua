-- app/content/statuses/charging.lua :: gathering power for a charged action (Solar Beam):
-- s:charge(ticks, "release") puts it on the caster with the spell's key and the name of
-- its stage (t.data.entity, t.data.release: names, never code). The caster can't act
-- meanwhile (its turn ends at the clock's next tick); when its ticks are up the status runs
-- out and releases the stage, the caster's action, even between its turns.

return {
	name = "Charging",
	description = "Gathering power: can't act until the charged action is released.",
	lore = [[
The stillness before a big spell. The caster draws in light or sun over a turn or two and
can do nothing else while it builds. Everyone in the fight can see it coming, which is why
the wise keep a healer close by. Once it is ready the spell goes off whether or not the
target has moved.]],
	icon = "charging",
	kind = "neutral",
	ticks = 1,
	blocks_action = true,
	messages = {
		blocked = "You are gathering power.",
		blocked_other = "The %s is gathering power.",
	},
	on_expire = function(t)
		t:release()
	end,
}
