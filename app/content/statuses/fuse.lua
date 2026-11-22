-- app/content/statuses/fuse.lua :: a lit fuse on an object (an explosive barrel): when it
-- burns down, the object goes off (its on_destroyed: docs/APP.md "Interactables and
-- targeting"). Only objects can be destroyed; on anyone else it just runs out. Water douses
-- it (the barrel's on_damage cures it).
return {
	name = "Lit Fuse",
	description = "Burning down: when it runs out, the object it is on goes off.",
	kind = "neutral",
	ticks = 2,
	on_expire = function(t)
		if t.bearer.side == "object" then t.bearer:destroy() end
	end,
}
