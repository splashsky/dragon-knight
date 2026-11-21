-- app/content/statuses/sleep.lua :: asleep (the original game's monster sleep, now a status
-- anyone can have; id 1). The Sleep spells put it on (s.target:sleep(chance), the same as
-- s.target:afflict("sleep", { chance = n })). At the start of each of its turns the
-- sleeper wakes up when rand(1, 15) > chance (it then acts that turn); while asleep it
-- can't act. It lasts until it wakes up or the fight ends.
local function who(t)
	if t.bearer.is_player then return "_you" end
	if t.bearer.side == "ally" then return "_ally" end
	return ""
end

return {
	name = "Asleep",
	description = "Can't act. Each turn there is a chance in 15 (its strength) that it stays asleep.",
	lore = [[
A sleeping spell, or a dose of sleepwort in a drink, lays a creature down where it stands.
Sleep takes hold quickly and lets go slowly, and each turn there is a small chance of
waking. A sleeping monster is no less dangerous when it wakes, and a sleeping adventurer
is the first thing a bandit looks for. Strong sleepers are harder to put down, and some
never sleep at all.]],
	kind = "harmful",
	tick_on = "turn_start",
	blocks_action = true,
	data = { chance = 5 },
	messages = {
		woke = "The monster has woken up.",
		still = "The monster is still asleep.",
		woke_you = "You have woken up.",
		still_you = "You are still asleep.",
		woke_ally = "Your %s has woken up.",
		still_ally = "Your %s is still asleep.",
	},
	on_tick = function(t)
		local suffix = who(t)
		if t:roll(1, 15) > t.data.chance then
			t:expire()
			t:say("woke" .. suffix, t.bearer.name)
		else
			t:say("still" .. suffix, t.bearer.name)
		end
	end,
}
