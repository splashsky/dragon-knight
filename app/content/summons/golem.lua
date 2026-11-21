-- app/content/summons/golem.lua :: a stone golem that stands beside the player (the Raise Golem
-- spell: s:summon("golem", { turns = 4 })). Very tough and slow: it hits hard now and then
-- and soaks up blows meant for the player.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a.target:hurt(damage)
	a:say("smash", a.self.name, damage)
end

return {
	name = "Golem",
	description = "Smashes the monster every round, and takes a lot of hits.",
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
