-- app/content/statuses/regen.lua :: recovers HP at the end of each turn; outside fights
-- (scope "both": a world status) after each move on the map.
return {
	name = "Regenerating",
	description = "Recovers hit points every turn, or every move outside fights.",
	lore = [[
A warm, steady healing that works on its own, from a prayer, a salve or a spell that
someone has left running. In a fight it closes wounds a little each turn. On the road it
does the same after each step, which is why the old travelers never bothered with an inn
for the first few days. It runs out after a while and does not stack with itself.]],
	icon = "regen",
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
