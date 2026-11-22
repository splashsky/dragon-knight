-- app/content/interactables/steam_vent.lua :: a crack in the Ashlands' cinders breathing steam
-- (docs/APP.md "Interactables and targeting"). Every third tick it scalds one creature at
-- random, after a tick's warning. A water hit (which barely hurts it) quenches it into one
-- great eruption that scalds everyone; an earth blow that brings it down plugs it for good.
local function scald(o, who, pct, min)
	local dealt = who:hurt(math.max(min, who.maxhp * pct // 100), "water")
	if who.is_player then o:say("scald_you", dealt) else o:say("scald", who.name, dealt) end
end

return {
	name = "Steam Vent",
	description = "A crack in the cinders spitting steam. Every 30 seconds it scalds one creature at random (12% of its "
		.. "hit points, as water), with a warning ten seconds before. A water hit sets it off at once, scalding everyone "
		.. "for 30%; earth plugs it.",
	lore = [[
The Ashlands' cinders are full of cracks, and some of them breathe steam with a hiss that
the people of Endworld learn to hear. The hiss comes a turn before the scald, which is time
to step aside if you are paying attention. Some say a splash of water will set the whole
crack off at once, and a few fools have tried it. Endworld's masons pile rubble on the
cracks they can reach, and leave the rest to take their chances.]],
	icon = "steam_vent",
	hp = 20,
	hp_per_level = 3,
	resist = { neutral = 50, earth = -50, fire = 100, water = 90 },   -- water barely hurts it (not 100: a spell refuses an immune target): it sets it off
	spawn = {
		{ fields = { "cinders" }, chance = 15 },
	},
	-- t: ticks since the last scald; a scald is 12% of the creature's max HP (at least 4), the great
	-- eruption 30% of everyone's (at least 6)
	data = { t = 0, scald_pct = 12, scald_min = 4, great_pct = 30, great_min = 6 },
	messages = {
		placed = "A crack in the black cinders breathes a plume of yellow steam.",
		hiss = "The vent hisses and spits steam.",
		scald = "The vent scalds the %s for %d damage.",
		scald_you = "The vent scalds you for %d damage.",
		great = "The vent roars, quenched into one great eruption!",
		capped = "The vent is capped with rubble.",
		dead = "The vent chokes and goes quiet.",
	},
	on_place = function(o) o:say("placed") end,
	on_damage = function(o, _, element)
		if element ~= "water" then return end
		o.data.t = 0
		o:say("great")
		for _, h in ipairs(o.combatants) do scald(o, h, o.data.great_pct, o.data.great_min) end
	end,
	on_tick = function(o)
		local d = o.data
		d.t = (d.t + 1) % 3
		if d.t == 2 then return o:say("hiss") end
		if d.t ~= 0 or #o.combatants == 0 then return end
		scald(o, o.combatants[o:roll(1, #o.combatants)], d.scald_pct, d.scald_min)
	end,
	on_destroyed = function(o, element)
		o:say(element == "earth" and "capped" or "dead")
	end,
}
