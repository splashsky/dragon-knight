-- app/content/spells/plague.lua :: the Plague spell: the strongest venom there is, a
-- long-lasting poison that also weakens the monster's blows (the venom status with bigger
-- numbers). Learned by no class by default.
-- learned: mage 83
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	s.target:afflict("venom", { turns = s.power, min = s.data.min, max = s.data.max, pct = s.data.pct })
	s:say("cast", s.name, s.power)
end

return {
	name = "Plague",
	description = "Infects the monster with a sickness that eats its hit points and weakens its blows for several turns. Some monsters are immune.",
	lore = [[
Plague is what Venom becomes when the Mage has more time and fewer scruples. The sickness
takes hold quickly, spreads through the blood and leaves the monster too weak to swing
properly for many turns. Gaia's priests in Hambry will not teach it, and the Mages who do
know it say that is the only sensible reason to keep it to themselves.]],
	mp = 45,
	power = 6,                  -- how many turns the sickness lasts
	data = { min = 18, max = 32, pct = 35 },   -- hit points per turn, percent less damage dealt
	uses = { statuses = { "venom" } },
	messages = {
		cast = "You have cast the %s spell. The monster is infected for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {
			cast = "The monster casts %s. You are infected for %d turns.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
