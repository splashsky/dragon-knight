-- app/content/spells/tithe.lua :: the Tithe spell: the caster gives up hit points to recover
-- magic points. Learned by no class by default.
-- learned: mage 57; warrior 32; paladin 36
local function price(s)
	return math.floor(s.caster.maxhp * s.data.cost / 100)
end

return {
	name = "Tithe",
	description = "Costs the caster some hit points to restore magic points, in a fight or out of it.",
	lore = [[
The old rule is that a Paladin pays for everything, and Tithe is the most literal form of
the rule: a little of your own blood is handed back as Magic Points. The priests in Bris
call it the cheapest mana in the realm, which is true only if you can spare the blood. It
is refused when the cost would leave you with nothing.]],
	icon = "tithe",
	mp = 1,
	power = 15,                 -- percent of the maximum MP it restores
	data = { cost = 12 },       -- percent of the maximum HP the caster gives up
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, gave up %d Hit Points, and gained %d Magic Points.",
		full = "Your Magic Points are already full. Please go back and try again.",
		weak = "You have too few Hit Points to give any up. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s, gives up %d Hit Points and gains %d Magic Points.",
		},
	},
	-- refused (costs nothing) at full MP, or when the cost would not leave at least 1 HP
	can_cast = function(s)
		if s.caster.mp >= s.caster.maxmp then return s:refuse("full") end
		if s.caster.hp <= price(s) then return s:refuse("weak") end
	end,
	cast = function(s)
		local cost = price(s)
		s.caster:hurt(cost)
		local restored = s.caster:heal("mp", math.floor(s.caster.maxmp * s.power / 100))
		s:say("cast", s.name, cost, restored)
	end,
}
