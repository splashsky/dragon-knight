-- app/content/statuses/poison.lua :: loses HP at the end of each of its turns: rand(min,
-- max) (t.data: the file's numbers, or what the spell applied it with).
local function tick(t)
	local damage = t:roll(t.data.min, t.data.max)
	t.bearer:hurt(damage)
	if t.bearer.is_player then
		t:say("hurt_you", damage)
	else
		t:say("hurt", t.bearer.name, damage)
	end
end

return {
	name = "Poisoned",
	description = "Loses hit points at the end of every turn.",
	kind = "harmful",
	tick_on = "turn_end",
	turns = 3,
	data = { min = 2, max = 5 },
	messages = {
		hurt = "The %s takes %d poison damage.",
		hurt_you = "You take %d poison damage.",
	},
	on_tick = tick,
}
