-- app/content/summons/wolf.lua :: a wolf that fights alongside the player (the Call Wolf
-- spell: s:summon("wolf", { turns = 5 })). act runs once per round after the player's
-- turn, at a target the fight picks (a.target); monsters may attack it instead of the
-- player (50/50 with one ally), with its defense and dexterity in place of the player's.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a.target:hurt(damage)
	a:say("bite", a.self.name, damage)
end

return {
	name = "Wolf",
	description = "Bites the monster every round.",
	hp = 30,
	attack = 12,
	defense = 5,
	dexterity = 4,
	turns = 5,
	messages = {
		bite = "Your %s bites the monster for %d damage.",
		gone = "Your %s runs off into the wild.",
	},
	act = act,
	on_expire = function(a)
		a:say("gone", a.self.name)
	end,
}
