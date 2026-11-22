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
	lore = [[
A poison in the blood, from a bite, a barbed spine or a cup of something bought from the
wrong stall. It hurts a little different each turn, sometimes worse, sometimes hardly at
all. It wears off on its own in a few turns, and an herb or a cure stops it sooner.
Nobody in Midworld has ever died of a single dose, only of three.]],
	icon = "poison",
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
