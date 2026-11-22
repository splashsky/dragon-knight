-- app/content/spells/doom.lua :: a death sentence (the doom status: app/content/statuses/doom.lua).
-- The target takes shadow damage, a share of the caster's own attack, when the ticks run out,
-- unless it is cured first. Learned by no class by default: monsters cast it.
local function cast(s)
	if s.target:immune_to("shadow") then return s:say("immune", s.name) end
	local damage = s.caster.attack * s.data.pct // 100
	if not s.target:afflict("doom", { ticks = s.power, damage = damage }) then
		return s:say(s.target:ward("doom") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s:seconds(s.power))
end

return {
	name = "Doom",
	description = "Names the day the target dies: in 40 seconds it takes shadow damage of half the caster's attack, unless a cure for harmful effects lifts it first. Some monsters are immune.",
	lore = [[
The Doomers on the roads near Gilead keep the book, and Doom is how they close the page.
A creature that is doomed has forty seconds to find a cure before the sentence is
carried out: a heavy blow of shadow, about half the caster's attack. Any cure for
harmful effects will lift it, and priests in Gilead keep one ready for anyone who has
been named in the book. The Doomer does not argue the sentence. It only says that the
page is closed.]],
	icon = "doom",
	mp = 30,
	power = 4,                  -- how many ticks until the doom falls
	data = { pct = 50 },        -- percent of the caster's attack it deals when it falls
	uses = { statuses = { "doom" } },
	messages = {
		cast = "You have cast the %s spell. The monster is doomed in %d seconds.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You are doomed in %d seconds.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
