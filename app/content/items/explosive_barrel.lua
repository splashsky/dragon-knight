-- app/content/items/explosive_barrel.lua :: a keg of blasting powder the player rolls onto the
-- field (the object explosive_barrel: app/content/interactables/explosive_barrel.lua). Fights
-- only; it costs the turn, and is refused when three objects already stand. Monsters carry
-- it too: their barrel blasts by their attack. Fire or lightning lights it, and when it goes it
-- blasts everyone on the field with fire, the thrower too.
return {
	name = "Explosive Barrel",
	description = "Rolls a keg of blasting powder onto the field (three objects at most). Fire or lightning lights its fuse, "
		.. "water douses it; when it goes it blasts everyone, you too, with fire: 3 + 5 per 4 of your levels, 80% to 100% of it.",
	icon = "explosive_barrel",
	category = "consumable",
	price = 180,                    -- a Hi-Potion's (a Fire Flask is 50, an Acid Vial 120)
	max_stack = 5,
	usable_in = "fight",
	target = "self",
	data = { base = 3, per_level = 5, levels = 4, monster = 40 },   -- a player's blast: base + per_level * level // levels; a monster's: its attack * monster / 100
	messages = {
		used = "You roll the %s onto the field.",
		no_room = "There is no room for another object on the field.",
		enemy = {
			used = "The monster rolls a keg of blasting powder onto the field.",
		},
	},
	uses = { interactables = { "explosive_barrel" } },
	can_use = function(u)
		if u.place_room < 1 then return u:refuse("no_room") end
	end,
	use = function(u)
		local d = u.data
		local blast = u.by_player and d.base + d.per_level * u.caster.level // d.levels or u.caster.attack * d.monster // 100
		u:place("explosive_barrel", { blast = math.max(blast, 1) })
		u:say("used", u.name)
	end,
}
