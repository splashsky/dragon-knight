-- app/content/spells/hurt.lua :: the Hurt spell (the original game's spell 6).
-- The behaviour is a free-standing local function (heal.lua shows inline ones); the
-- messages are data, so cast says them by key (s:say("hit", ...)) to use admin overrides.
local function cast(s)
	if s.target.immune ~= 0 then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)   -- the original's rand(max * 5/6, max)
	s.target:hurt(damage)
	s:say("hit", s.name, damage)
end

return {
	name = "Hurt",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	lore = [[
The first real attack spell most Mages learn, and the one they practise on sparring dummies
until the dummies complain. It sends a sharp jolt through a monster's body, which hurts even
when it does not kill. Wise casters cast it early, before the enemy has settled into its stride.]],
	icon = "hurt",
	mp = 5,
	power = 15,                 -- the most damage it deals
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = cast,
}
