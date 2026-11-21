-- app/content/spells/stand_fast.lua :: the Stand Fast spell: the caster takes a wound in
-- exchange for a strong defense buff until the end of the fight. Learned by no class by
-- default.
-- learned: warrior 30
local function price(s)
	return math.floor(s.caster.maxhp * s.data.cost / 100)
end

return {
	name = "Stand Fast",
	description = "Costs the caster some hit points to reduce the damage it takes until the end of the fight.",
	lore = [[
Warriors in Kalle say a man who will not step back never needs healing in time. Stand Fast
is a shout, a spent breath and a little blood: the caster takes a wound now for a much
firmer guard for the rest of the fight. It is refused when the wound would finish you, so
cast it early or not at all.]],
	mp = 8,
	power = 28,                 -- percent less damage taken
	data = { cost = 12 },       -- percent of the maximum HP the caster gives up
	target = "self",
	messages = {
		cast = "You have cast the %s spell, gave up %d Hit Points, and will gain %d%% defense until the end of this fight.",
		weak = "You have too few Hit Points to stand fast. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s, gives up %d Hit Points and will take %d%% less damage.",
		},
	},
	-- refused (costs nothing) when the cost would not leave at least 1 HP
	can_cast = function(s)
		if s.caster.hp <= price(s) then return s:refuse("weak") end
	end,
	cast = function(s)
		local cost = price(s)
		s.caster:hurt(cost)
		s.caster:buff("defense", s.power)
		s:say("cast", s.name, cost, s.power)
	end,
}
