---
id: monsters/undead
summary: The walking dead and the things of dread: skeletons, ghouls, wraiths, the five liches and their courts, and the fright and doomer kin.
related: [monsters/fey-and-spirits, monsters/people, magic/elements, magic/afflictions, magic/paladins, legends/upper-echelon, world/overview]
sources: [app/content/monsters/skeleton.lua, app/content/monsters/megaskeleton.lua, app/content/monsters/ultraskeleton.lua, app/content/monsters/ghoul.lua, app/content/monsters/wraith.lua, app/content/monsters/megawraith.lua, app/content/monsters/ultrawraith.lua, app/content/monsters/liche.lua, app/content/monsters/liche_master.lua, app/content/monsters/liche_prince.lua, app/content/monsters/liche_lord.lua, app/content/monsters/liche_king.lua, app/content/monsters/fear.lua, app/content/monsters/fright.lua, app/content/monsters/horror.lua, app/content/monsters/terror.lua, app/content/monsters/doomer.lua, app/content/monsters/megadoomer.lua, app/content/monsters/ultradoomer.lua, app/content/fields/miasma.lua, app/content/spells/doom.lua, continuity.md#where-monsters-live]
---

# The dead and the things of dread

Bodies that would not stay buried, and the cold things that gather where people died badly.
Restless spirits that have no body (ghosts, specters, haunts) are in `monsters/fey-and-spirits.md`;
the dead man in plate (the Knight) is in `monsters/people.md`.

## Nature

All of them are weak to holy light, resist shadow, and cannot be poisoned (poison does
nothing to them). Most cannot be put to sleep. Steel
works on the bodies; the wraiths resist half of it. A Paladin's prayer and a Blessed Mace
(`magic/paladins.md`, `things/gear.md`) are the answer; consecrated ground makes shadow weaker
and holy stronger. Gravediggers cover bodies with lime and stone, which slows them but does not
stop them. Priests in Midworld bless a grave for a few gold.

## Skeletons (levels 10 to 16)

- **Skeleton** (`skeleton`, 10). The bones of a fighter, raised to walk the graveyards outside
	the towns by a spell nobody has bothered to undo. No memory of its name. Its rattle carries
	on a still night, which is how the watch knows it is coming.
- **Megaskeleton** (`megaskeleton`, 13). Several skeletons fused by a careless necromancer:
	bigger, heavier, a little confused. Shambles down the old roads near Kalle dragging a cart
	of bones. Under a third of its life it reassembles once (a Life).
- **Ultraskeleton** (`ultraskeleton`, 16). The top of the line: a bone frame reinforced with
	iron and banded with old charms, guarding crypts past Gilead. It does not speak; its armor
	does. It rages after its opening swing, so the second blow is always harder.

## Ghoul and wraiths

- **Ghoul** (`ghoul`, 7). A corpse that has been up too long, hunting a warm meal on the old
	battlefields near Narcissa; not particular whether the dead or the living. Knits itself under
	half life (Grit). Sleep takes only half the time.
- **Wraith** (`wraith`, 16). What a murderer becomes when nobody buries the body; it haunts the
	lonely crossroads where the killing was done. Quiet and hard to hit. Weakens you in its
	first two turns and drains you once it is under half. Its touch leaves a chill for days.
- **Megawraith** (`megawraith`, 21). A wraith grown fat on a battlefield's dead, taller than a
	door; it drives where lesser wraiths drift. The dead of Gilead are said to have stopped
	reaching the afterlife because of them. Priests advise holy water and running, in that order.
- **Ultrawraith** (`ultrawraith`, 26). Dead long enough to forget most of what it was and to
	remember exactly how it died. In ruined churches and toll houses beyond Hambry, drawn to the
	warmth of a campfire. Calls the night, drains you in the dark, weakens you.

## The Liche line

A dead mage who would not stay buried is a **liche**: kept upright by a cold will and a spell
repeated for centuries. They hoard books, drift toward old libraries, and are slow to start but
hard to stop, so close the distance before the first spell is finished. All cast as Mages,
without sleep-locks, summons or weather. Two courts are told of.

**The Dead School beyond Narcissa** (the liches that teach):
- **Liche** (`liche`, 35). Hoards every book it can steal. Waits two turns, then drains you
	(Withering) and from its third turn maims.
- **Liche Master** (`liche_master`, 38). Runs the dead school, where the lessons are given in
	fire and the exams fought out with the pupils. Its exam goes in order, one element a turn:
	fire (Cinder Lash), frost (Frostbite), lightning (Thunderbolt). It expects visitors to know
	which spell they are facing.
- **Liche Prince** (`liche_prince`, 40). Rules the school above its Master: a brass crown on a
	skull that forgot its name, a great library with the stolen books chained to the shelves.
	Few spells, all strong (Rend, Withering). Scholars say he never wastes a word, and that this
	is the most frightening thing about him.

**The King's crypts** (the liches that keep accounts):
- **Liche Lord** (`liche_lord`, 42). The steward of the Liche King's crypts, who keeps the
	tithe ledgers and bone-chambers. Precise, patient, fond of records. Marks you from his
	second turn ("Entry recorded"), rends, drains, and guards under half ("Losses are also
	recorded"). Travellers with a receipt from one of his clerks are let past; the rest are
	written down as missing.
- **Liche King** (`liche_king`, 44). Once a lord of the old kingdom, bound to a throne of bone
	so his rule would outlast his heart. His court of the dead meets in the crypts under Kalle,
	where every chair is full. He sends servants to collect the tithe of gold from the living
	and counts every coin himself. His court has three phases: first the grave-fog (Miasma) and
	a heavy hand, below two thirds a drain and a Rend, below a third he guards himself. He
	drinks a potion when badly hurt.

Miasma, the "aura of the liches" (`magic/afflictions.md`, `magic/elements.md`), is what a
liche leaves in the air; a Paladin's Consecrate clears it.

## The fright and doomer kin

Cold that gathers where there is fear and a bad conscience; ward off sleep, poison and venom,
resist shadow, weak to holy light. Their numbers grow with the road: from the fright in the
cellars to the doomers at the crossroads.

- **Fear** (`fear`, 23). Not a monster in the usual sense: the cold that gathers in a traveller's
	mind on the road to Endworld. It wears whatever the hero fears most. Weakens you, and puts you
	to sleep only once you are under half life. Soldiers of Gilead have been found sitting by the
	road, unharmed and unable to say why they stopped.
- **Fright** (`fright`, 25). Pale, thin; in cellars and under the floors of abandoned mills.
	Miners near Hambry say it follows the sound of their picks into the dark. Its touch would
	stop a heart, and it takes its time.
- **Horror** (`horror`, 27). What the fright kin become when they have fed a long time: taller
	than a door and mostly mouth, in the clothes of those it ate. Near Gilead one stood in a road
	without moving until a lantern was lit, and then it was close. Withers and weakens.
- **Terror** (`terror`, 31). Grey cloth and long fingers, at a camp after the last fire is low;
	it stays near the old crossroads by Endworld where the gallows stood. Puts the lamp out
	(nightfall), lulls you to sleep in the dark when you are under half, drains the sleeper,
	rages at night. A lamp does not frighten it; a companion who stays awake usually does.
- **Doomer** (`doomer`, 32). The last of the kin seen above ground and the only one that talks:
	the look of a judge, a long black coat, a book kept open at a page nobody can read. It names
	the things you have done, then the day you will die (Doom). A cure for harmful effects lifts
	it; priests in Gilead keep one ready.
- **Megadoomer** (`megadoomer`, 34). A hooded figure at the crossroads south of Gilead that counts.
	Those who pass in silence are left alone; those who answer find their own number running
	down faster. Dooms you, drains you while the doom ticks, brings the night under half.
- **Ultradoomer** (`ultradoomer`, 36). The Megadoomer's elder, in the dead hall beneath the
	Hambry road, keeping a count that is nearly done. Its hood hides a face nobody has described
	twice alike. It counts: "Four. Three. Two. One. Zero." Scholars in Gilead say that when it
	reaches the end the road will be quieter for a while.

## Where they are met

Levels 7 to 16 near Roma and Bris; 21 to 27 about Kalle and Narcissa; the liches, doomers and
dread kin from 31 on, out toward Hambry and Gilead (`world/overview.md`). The lore's places
(Narcissa, Kalle, Gilead) are where each kind is told of, not where its level is met: see
`continuity.md#where-monsters-live`.
