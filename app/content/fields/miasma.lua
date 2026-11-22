-- app/content/fields/miasma.lua :: a miasma (an aura: only from a spell, the necromancers'):
-- poison and shadow strong, holy light weak, poisons half again as strong.
return {
	name = "Miasma",
	description = "A foul, clinging miasma: poison and shadow are stronger, holy light weaker, and poisons bite half again as hard.",
	icon = "miasma",
	group = "aura",
	damage = { poison = 30, shadow = 25, holy = -25 },
	statuses = {
		poison = { scale = { min = 150, max = 150 } },
		venom = { scale = { min = 150, max = 150 } },
	},
	messages = {
		begins = "A sickly miasma creeps over the field.",
		ends = "The miasma thins and drifts away.",
	},
}
