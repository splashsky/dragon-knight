-- app/content/summons/spirit.lua :: a spirit that fights alongside the player (the Call Spirit
-- spell: s:summon("spirit", { turns = 6 })). Hard to pin down: a high defense and quick, so
-- monsters often miss it, and it hits for a fair amount.
local function act(a)
	local damage = a:roll(a.self.attack // 2, a.self.attack)
	a.target:hurt(damage)
	a:say("touch", a.self.name, damage)
end

return {
	name = "Spirit",
	description = "Strikes the monster with a cold touch every round.",
	hp = 90,
	attack = 30,
	defense = 40,
	dexterity = 30,
	turns = 6,
	messages = {
		touch = "Your %s touches the monster for %d damage.",
		gone = "Your %s fades back into the air.",
	},
	act = act,
	on_expire = function(a)
		a:say("gone", a.self.name)
	end,
}
