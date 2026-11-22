-- app/content/items/weakening_dust.lua :: a thrown dust that weakens the monster's blows
-- (the weakened status; a ward against it may stop it, and one of 100% refuses it).
-- Fights only.
return {
	name = "Weakening Dust",
	description = "Throws a pale dust that makes the monster deal less damage for a few turns.",
	lore = [[
A pale, gritty powder from the salt pans at the mouth of the Kalle road, mixed with a
bitter white root that the pan-men dig up at night. Thrown at a monster's face, it stings
the eyes and takes the weight out of its swings for a few turns. A soldier in Kalle says
it is the only thing he has seen that makes an ogre hesitate, and he says that as if it
were a grievance.]],
	icon = "weakening_dust",
	category = "consumable",
	price = 200,
	max_stack = 10,
	usable_in = "fight",
	power = 3,                      -- the turns it lasts
	data = { pct = 35 },            -- the percent of its damage taken away
	messages = {
		used = "You throw the %s. The monster deals less damage for %d turns.",
		immune = "You throw the %s, but the monster is immune to it.",
		resisted = "You throw the %s, but the monster resists it.",
	},
	uses = { statuses = { "weakened" } },
	can_use = function(u)
		if u.target:ward("weakened") == 100 then return u:refuse("immune", u.name) end
	end,
	use = function(u)
		if not u.target:afflict("weakened", { turns = u.power, pct = u.data.pct }) then
			return u:say("resisted", u.name)
		end
		u:say("used", u.name, u.power)
	end,
}
