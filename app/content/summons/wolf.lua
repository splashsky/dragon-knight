-- app/content/summons/wolf.lua :: a wolf that fights alongside the player (the Call Wolf
-- spell: s:summon("wolf", { turns = 5 })). act runs once per round after the player's
-- turn, at a target the fight picks (a.target); monsters may attack it instead of the
-- player (50/50 with one ally), with its defense and dexterity in place of the player's.
-- Its bite is of its element (`element`, neutral unless the file says otherwise), which its
-- handle shows as a.self.attack_element.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a:say("bite", a.self.name, a.target:hurt(damage, a.self.attack_element))
end

return {
	name = "Wolf",
	description = "Bites the monster every round.",
	lore = [[
A grey wolf that answers the call from the edge of the road and runs at the caster's side
until the fight is done. It is not tame, and it has no interest in being petted. It is
quick, fragile for its size, and will take a blow meant for the caster if the monster
happens to choose it. Hunters from Roma say it always leaves before the trouble does.]],
	icon = "wolf",
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
