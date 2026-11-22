-- app/content/spells/finishing_blow.lua :: the Finishing Blow spell (the last stroke a veteran knows where to place).
-- learned: warrior 60; paladin 84
-- Damage is a share of the caster's attack (up to power). Against a monster at a quarter of its maximum
-- HP or less the blow lands twice as hard.
return {
	name = "Finishing Blow",
	description = "Hurts the monster by a share of your attack, and twice as hard when it is badly hurt. Some monsters are immune.",
	lore = [[
Veterans call it the mercy stroke, though the monster rarely finds it merciful. It is
aimed at the gap under the ribs or the soft place behind the jaw, and it is the one
thing a Warrior learns only by losing a few fights first. Against a creature already
bleeding and staggering it is hardly a blow at all, just a formality with a sword.]],
	icon = "finishing_blow",
	mp = 20,
	power = 100,                -- the most damage it deals (twice that when it finishes)
	data = { pct = 100 },       -- percent of your attack it deals before that limit
	messages = {
		hit = "You have cast the %s spell for %d damage.",
		finish = "You have cast the %s spell for %d damage. The monster is finished.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
		enemy = {                    -- when a monster casts it
			hit = "The monster casts %s on you for %d damage.",
			immune = "The monster casts %s, but you are immune to it.",
		},
	},
	cast = function(s)
		if s.target.immune ~= 0 then return s:say("immune", s.name) end
		local top = math.min(s.power, math.floor(s.caster.attack * s.data.pct / 100))
		local damage = s:roll(math.floor(top * 5 / 6), top)
		if s.target.hp * 4 <= s.target.maxhp then
			damage = damage * 2
			s.target:hurt(damage)
			return s:say("finish", s.name, damage)
		end
		s.target:hurt(damage)
		s:say("hit", s.name, damage)
	end,
}
