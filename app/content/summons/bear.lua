-- app/content/summons/bear.lua :: a bear that fights alongside the player (the Call Bear
-- spell: s:summon("bear", { turns = 4 })). Slow to tire, hard hitting, and it takes a good
-- share of the monster's attention.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a.target:hurt(damage)
	a:say("maul", a.self.name, damage)
end

return {
	name = "Bear",
	description = "Mauls the monster every round.",
	hp = 80,
	attack = 22,
	defense = 8,
	dexterity = 3,
	turns = 4,
	messages = {
		maul = "Your %s mauls the monster for %d damage.",
		gone = "Your %s lumbers back into the trees.",
	},
	act = act,
	on_expire = function(a)
		a:say("gone", a.self.name)
	end,
}
