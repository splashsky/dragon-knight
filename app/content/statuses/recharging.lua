-- app/content/statuses/recharging.lua :: must recover after a big action (Hyper Beam):
-- s:recharge(turns) puts it on the caster, who can't act for that many turns (the fight
-- page offers only "Continue").
return {
	name = "Recharging",
	description = "Can't act: recovering from a powerful attack.",
	lore = [[
The strain after a spell that takes everything out of a caster. The arms go slack, the
breath comes hard, and for a turn there is nothing to do but wait. Mages say the spell was
worth it when it works, and that nobody remembers the turn afterwards. Monsters that are
big enough to shrug off such a spell are not affected by it at all.]],
	kind = "neutral",
	turns = 1,
	blocks_action = true,
	messages = {
		blocked = "You must recharge this turn.",
		blocked_other = "The %s must recharge this turn.",
	},
}
