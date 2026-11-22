-- app/content/statuses/fuse.lua :: a lit fuse on an object (an explosive barrel, a dead tree):
-- when it burns down, the object goes off (its on_destroyed: docs/APP.md "Interactables and
-- targeting"). Only objects can be destroyed; on anyone else it just runs out. Water douses
-- it (the object's on_damage cures it; a soaked bearer can't be lit: soaked's ward).
return {
	name = "Lit Fuse",
	description = "Burning down: when it runs out (20 seconds), the object it is on goes off.",
	icon = "fuse",
	kind = "neutral",
	ticks = 2,
	on_expire = function(t)
		if t.bearer.side == "object" then t.bearer:destroy() end
	end,
}
