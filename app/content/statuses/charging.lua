-- app/content/statuses/charging.lua :: gathering power for a charged action (Solar Beam):
-- s:charge(turns, "release") puts it on the caster with the spell's key and the name of
-- its stage (t.data.entity, t.data.release: names, never code). The caster can't act
-- meanwhile; at the start of its last turn the status runs out and releases the stage,
-- which is that turn's action.
local function tick(t)
	if (t.turns_left or 1) <= 1 then t:expire() end
end

return {
	name = "Charging",
	description = "Gathering power: can't act until the charged action is released.",
	kind = "neutral",
	tick_on = "turn_start",
	turns = 1,
	blocks_action = true,
	messages = {
		blocked = "You are gathering power.",
		blocked_other = "The %s is gathering power.",
	},
	on_tick = tick,
	on_expire = function(t)
		t:release()
	end,
}
