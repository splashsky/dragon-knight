-- app/content/statuses/regen.lua :: recovers HP at the end of each turn; outside fights
-- (scope "both": a world status) after each move on the map.
return {
	name = "Regenerating",
	description = "Recovers hit points every turn, or every move outside fights.",
	kind = "helpful",
	tick_on = "turn_end",
	scope = "both",
	turns = 5,
	data = { amount = 5 },
	messages = {
		heal = "The %s regenerates %d Hit Points.",
		heal_you = "You regenerate %d Hit Points.",
	},
	on_tick = function(t)
		local healed = t.bearer:heal("hp", t.data.amount)
		if healed == 0 then return end
		if t.bearer.is_player then t:say("heal_you", healed) else t:say("heal", t.bearer.name, healed) end
	end,
}
