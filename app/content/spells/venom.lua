-- app/content/spells/venom.lua :: the Venom spell: a stronger poison that also weakens the
-- monster's blows (app/content/statuses/venom.lua). Learned by no class by default.
-- learned: mage 33; warrior 82
local function cast(s)
	if s.target:immune_to("poison") then return s:say("immune", s.name) end
	if not s.target:afflict("venom", { turns = s.power, min = s.data.min, max = s.data.max, pct = s.data.pct }) then
		return s:say(s.target:ward("venom") == 100 and "immune" or "resisted", s.name)
	end
	s:say("cast", s.name, s.power)
end

return {
	name = "Venom",
	description = "Poisons the monster harder than Poison, and weakens its blows while it lasts. Some monsters are immune.",
	lore = [[
Apothecaries in Bris keep their venom in a locked cabinet and sell it by the drop. The spell
is cheaper than the vial and does the same work: it thickens the blood, so the monster
bleeds a little more every turn and hits a little softer. Paladins call it a sin and use
it anyway when a fight is going badly.]],
	icon = "venom",
	mp = 14,
	power = 4,                  -- how many turns the venom lasts
	data = { min = 6, max = 12, pct = 20 },   -- hit points per turn, percent less damage dealt
	uses = { statuses = { "venom" } },
	messages = {
		cast = "You have cast the %s spell. The monster is poisoned for %d turns.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		resisted = "You have cast the %s spell, but the monster resists it.",
		enemy = {
			cast = "The monster casts %s. You are poisoned for %d turns.",
			immune = "The monster casts %s, but you are immune to it.",
			resisted = "The monster casts %s, but you resist it.",
		},
	},
	cast = cast,
}
