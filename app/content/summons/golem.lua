-- app/content/summons/golem.lua :: a stone golem that stands beside the player (the Raise Golem
-- spell: s:summon("golem", { turns = 4 })). Very tough and slow: it hits hard now and then
-- and soaks up blows meant for the player.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a:say("smash", a.self.name, a.target:hurt(damage, a.self.attack_element))
end

return {
	name = "Golem",
	description = "Smashes the monster every round, and takes a lot of hits.",
	lore = [[
A figure of quarried stone, raised from the old foundations of a broken chapel and bound
to serve the one who speaks its name. It is as patient as the hills it came from and
rather more stubborn. It walks slowly, strikes seldom and hard, and stands in front of its
caster without being asked. The priests say the stone remembers what it was built to guard.]],
	icon = "golem",
	hp = 450,
	attack = 90,
	defense = 100,
	dexterity = 1,
	turns = 4,
	messages = {
		smash = "Your %s smashes the monster for %d damage.",
		gone = "Your %s crumbles back into rubble.",
	},
	act = act,
	on_expire = function(a)
		a:say("gone", a.self.name)
	end,
}
