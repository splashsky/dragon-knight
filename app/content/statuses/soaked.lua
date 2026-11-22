-- app/content/statuses/soaked.lua :: drenched (a tide pool's splash, a water spell that wants
-- it): the water puts out a fire at once and keeps most from catching, and makes lightning and
-- frost bite deeper. Declarative resistances and wards; only the first drenching has code.
return {
	name = "Soaked",
	description = "Drenched: takes 25% less fire damage, 30% more lightning and 10% more frost; burning is 60% warded off, a fuse can't be lit, and what burns is put out.",
	icon = "soaked",
	kind = "neutral",
	ticks = 3,
	resist = { fire = 25, lightning = -30, frost = -10 },
	ward = { burning = 60, fuse = 100 },
	messages = {
		out = "The water puts the fire out on the %s.",
		out_you = "The water puts the fire out on you.",
	},
	uses = { statuses = { "burning", "fuse" } },
	on_apply = function(t)
		if t.bearer:cure("burning") + t.bearer:cure("fuse") > 0 then
			if t.bearer.is_player then t:say("out_you") else t:say("out", t.bearer.name) end
		end
	end,
}
