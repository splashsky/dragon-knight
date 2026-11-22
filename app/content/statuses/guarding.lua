-- app/content/statuses/guarding.lua :: the player raised their guard (3.2: the Guard action
-- on the hotbar's key 9, and what a turn that ran out does: fight/act.lua act.guard). Weapon
-- attacks on the bearer deal less damage (pct, a quarter) until its next turn begins, when
-- the round ends it (fight/round.lua).
return {
	name = "Guarding",
	description = "Takes less damage (its percent) from weapon attacks until its next turn.",
	lore = [[
A shield raised, the feet set and the head kept low. It does nothing to the monster and is
no way to win a fight, but it takes the edge off the blows that come while one waits for a
better moment. Old soldiers say a fighter who has nothing better to do should do this, and
that most fighters have something better to do.]],
	icon = "guarding",
	kind = "helpful",
	data = { pct = 25 },
	modify_damage_taken = function(t, damage)
		return damage - math.floor(damage * (t.data.pct / 100))
	end,
}
