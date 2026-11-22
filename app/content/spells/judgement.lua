-- app/content/spells/judgement.lua :: the Paladin gathers holy light for a turn, then
-- strikes. The release stage deals the damage and heals the caster for a quarter of it.
-- A fight in progress is saved with names only, so the stage is referenced by name.
-- Learned by no class by default.
-- learned: paladin 64
local function release(s)
	if s.target:immune_to("holy") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	local dealt = s.target:hurt(damage, "holy")
	s:say("hit", s.name, dealt)
	local healed = s.caster:heal("hp", math.floor(dealt / 4))
	if healed > 0 then s:say("heal", healed) end
end

return {
	name = "Judgement",
	description = "Gathers holy light for a turn, then strikes the monster and heals you a little. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
A Paladin who can stand still long enough to pray will be rewarded with Judgement. It
takes a whole turn to gather, which is a long time in a fight, and the monster gets to
see it coming. The light that falls afterwards is holy and heavy, and some of it runs
back into the Paladin's own wounds, which is why the knights of Gilead still call it
the honest spell.]],
	icon = "judgement",
	mp = 32,
	power = 140,                -- the most damage it deals
	uses = { statuses = { "charging" } },
	messages = {
		charge = "You have cast the %s spell, and gather holy light.",
		hit = "The %s strikes for %d damage.",
		heal = "The %s restores %d Hit Points to you.",
		immune = "The %s strikes, but the monster is immune to it.",
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
