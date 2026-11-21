-- app/content/statuses/venom.lua :: a stronger poison than the poison status: it loses HP at
-- the end of each of its turns (rand(min, max)) and, while the venom lasts, deals less
-- damage (pct, the Venom spell's weakness). The Venom spell puts it on a monster.
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
	name = "Venomous",
	description = "Loses hit points every turn, and deals less damage while it lasts.",
	kind = "harmful",
	tick_on = "turn_end",
	turns = 4,
	data = { min = 4, max = 9, pct = 20 },
	messages = {
		hurt = "The %s takes %d venom damage.",
		hurt_you = "You take %d venom damage.",
	},
	on_tick = tick,
	modify_damage_dealt = function(t, damage)
		return damage - math.floor(damage * (t.data.pct / 100))
	end,
}
