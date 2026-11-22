-- app/content/spells/inferno.lua :: the Inferno spell: a fire that does not go out, burning
-- every foe and every object on the field (an area spell) for a large fixed amount on every
-- tick of the clock (app/content/statuses/burning.lua, as Ember does with smaller numbers).
-- It lights every barrel and burns every hive.
-- learned: mage 88
local function cast(s)
	s:say("cast", s.name)
	for _, t in ipairs(s.targets) do
		local kind
		if t:immune_to("fire") then
			kind = "immune"
		elseif t:afflict("burning", { ticks = s.power, amount = s.data.amount }) then
			if t.is_player then s:say("burn_you", s:seconds(s.power)) else s:say("burn", t.name, s:seconds(s.power)) end
		else
			kind = t:ward("burning") == 100 and "immune" or "resisted"
		end
		if kind and t.is_player then s:say(kind .. "_you", s.name) elseif kind then s:say(kind, t.name, s.name) end
	end
end

return {
	name = "Inferno",
	description = "Sets every monster and every object on the field ablaze: each burns for a great many hit points every 10 seconds. Some monsters are immune.",
	lore = [[
Ember is a spark in a haystack. Inferno is the haystack, the barn and the field behind it. A
Mage who casts it only has to stay out of the smoke while the target burns. The old
masters in Endworld say it was never meant for a fight: it was meant for clearing roads, and
roads are what it clears.]],
	icon = "inferno",
	area = true,                -- burns every foe and object (s.targets)
	mp = 45,
	power = 5,                  -- how many ticks the fire burns
	data = { amount = 40 },     -- hit points it burns away each tick
	uses = { statuses = { "burning" } },
	messages = {
		cast = "You have cast the %s spell, and fire sweeps the field.",
		burn = "The %s burns for %d seconds.",
		immune = "The %s is immune to the %s.",
		resisted = "The %s resists the %s.",
		-- the player's cast never hits the player: these only name the keys that messages.enemy words
		burn_you = "You catch fire and burn for %d seconds.",
		immune_you = "You are immune to the %s.",
		resisted_you = "You resist the %s.",
		enemy = {
			cast = "The monster casts %s, and fire sweeps the field.",
			burn = "The %s burns for %d seconds.",
			burn_you = "You burn for %d seconds.",
			immune = "The %s is immune to the %s.",
			immune_you = "You are immune to the %s.",
			resisted = "The %s resists the %s.",
			resisted_you = "You resist the %s.",
		},
	},
	cast = cast,
}
