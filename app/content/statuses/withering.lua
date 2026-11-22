-- app/content/statuses/withering.lua :: drains the bearer at the end of each of its turns:
-- the damage (rand(min, max)) is taken from it and, when the caster is still in the fight,
-- added to the caster's HP. The Withering spell puts it on a monster.
local function tick(t)
	local damage = t:roll(t.data.min, t.data.max)
	t.bearer:hurt(damage)
	if t.source ~= nil and t.source.hp > 0 then t.source:heal("hp", damage) end
	if t.bearer.is_player then
		t:say("hurt_you", damage)
	else
		t:say("hurt", t.bearer.name, damage)
	end
end

return {
	name = "Withering",
	description = "Loses hit points every turn; the caster gains what it loses.",
	lore = [[
A dark working that pulls the life out of a creature and into the caster. The victim
shrivels a little more each turn, and the caster's wounds close by the same amount. Those
who study such magic in the old libraries say it was banned for a reason, and that the
reason is still standing in the road to Endworld.]],
	icon = "withering",
	kind = "harmful",
	tick_on = "turn_end",
	turns = 3,
	data = { min = 14, max = 24 },
	messages = {
		hurt = "The %s withers, losing %d Hit Points to you.",
		hurt_you = "You wither, losing %d Hit Points.",
	},
	on_tick = tick,
}
