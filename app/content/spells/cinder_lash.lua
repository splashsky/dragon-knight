-- app/content/spells/cinder_lash.lua :: a whip of fire that bites twice as hard when the
-- monster is still unhurt (at full HP): the first blow is the one that counts.
-- learned: mage 23
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	if s.target.hp >= s.target.maxhp then
		damage = damage + s:roll((s.power / 6) * 5, s.power)
		s.target:hurt(damage)
		return s:say("full", s.name, damage)
	end
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Cinder Lash",
	description = "Lashes the monster with fire, and does double damage while it is at full Hit Points. Some monsters are immune.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
A Mage who has been on the road a week learns to read a monster before lashing it. An
unhurt beast has its whole strength, and a Cinder Lash laid on it while it is still
fresh does double the harm. Once the monster has been bloodied the lash is only a fine
bit of fire, so Roma's guild masters tell their pupils to cast it first and talk later.]],
	mp = 16,
	power = 36,                 -- the most damage it deals (twice this at full HP)
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		full = "You have cast the %s spell at full strength, for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
