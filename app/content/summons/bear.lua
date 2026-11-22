-- app/content/summons/bear.lua :: a bear that fights alongside the player (the Call Bear
-- spell: s:summon("bear", { ticks = 4 })). Slow to tire, hard hitting, and it takes a good
-- share of the monster's attention.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a:say("maul", a.self.name, a.target:hurt(damage, a.self.attack_element))
end

return {
	name = "Bear",
	description = "Mauls the monster every round.",
	lore = [[
A brown bear from the woods north of Midworld, called out of the trees with a horn and a
few words the caster would rather not repeat. It is slow to tire and not fussy about what
it hits. Trappers say it is more bad-tempered than hungry, which is some comfort, and it
never lingers after the fight is done.]],
	icon = "bear",
	hp = 80,
	attack = 22,
	defense = 8,
	dexterity = 3,
	ticks = 4,
	messages = {
		maul = "Your %s mauls the monster for %d damage.",
		gone = "Your %s lumbers back into the trees.",
	},
	act = act,
	on_expire = function(a)
		a:say("gone", a.self.name)
	end,
}
