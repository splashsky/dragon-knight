-- app/content/statuses/recharging.lua :: must recover after a big action (Hyper Beam):
-- s:recharge(turns) puts it on the caster, who can't act for that many turns (the fight
-- page offers only "Continue").
return {
	name = "Recharging",
	description = "Can't act: recovering from a powerful attack.",
	kind = "neutral",
	turns = 1,
	blocks_action = true,
	messages = {
		blocked = "You must recharge this turn.",
		blocked_other = "The %s must recharge this turn.",
	},
}
