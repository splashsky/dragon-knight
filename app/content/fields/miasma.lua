-- app/content/fields/miasma.lua :: a miasma (an aura: only from a spell, the necromancers'):
-- poison and shadow strong, holy light weak, poisons half again as strong.
return {
	name = "Miasma",
	description = "A foul, clinging miasma: poison and shadow are stronger, holy light weaker, and poisons bite half again as hard.",
	lore = [[
Miasma is the aura of the liches, and it rises off the ground wherever one of them has
cast it. The dead are slow to stay buried in it, and the air stays thick long after the
caster has gone. It clings to clothes and hair, and poison bites half again as hard. The
holy men of Gilead keep the chapel doors shut while it lasts.]],
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
