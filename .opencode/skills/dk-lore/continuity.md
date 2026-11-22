# Continuity

Decisions about the world's facts: where two facts collided, what was decided and why; and
open questions until they are decided. Newest first. A chunk may cite a decision as a
source (`continuity.md#<heading>`).

## Decided

### Where monsters live

Monsters are met by the ring, not by the land or the town. A monster of level L is met from 5L-5
to 5L+9 tiles from Midworld (`app/fight/combat.lua` monster_levels), but a monster's lore names a
town or a land for where its kind is "said to" live, and for many monsters the two disagree: a
level-8 Rogue "works the Hambry road" (met 35 to 49 tiles out; Hambry is 170), a level-28 Wyrm
lives "under the cliffs north of Roma" (met 135 to 149 out). The mechanics win: where a monster is
met follows its level, and the place in its lore is a rumour of where it comes from, read as in
`world/overview.md` ("near" is the town's land and the next one out; "past" and "beyond" are farther
along the arm). The monster chunks list every monster with its level and give the lore's place as
told, and `monsters/others.md` states the rule; new lore should name a town whose ring fits the
level. The lore of these monsters is **not** rewritten to match: only an impossible place was fixed
(the Fire Wyrm, below).

Monsters whose lore names a place their level cannot have (level, place in the lore):

- Near Midworld, Roma and Kalle: troll (17, between Midworld and Roma), ghost (6, the road to
	Kalle), wyrm (28, north of Roma), serafiend (38, the hills above Roma), blaze (31, Roma to Bris),
	nisse (19, around Roma), shade (3, north of Kalle), nightshade (6, near Kalle), flame (28, Bris).
- Near Narcissa and Hambry: frost raven and ghoul (7, Narcissa), drakefin (8, Hambry), rogue (8,
	the Hambry road), hellion (16, Hambry), sylph (15, beyond Hambry), orc and dark scorpion (15, beyond
	or past Narcissa), wizard (20, past Narcissa), dawk and uruk (19, 20, past Narcissa), dawkin
	(21, beyond Hambry), grey bear (21, past Hambry and in Gilead).
- Near Gilead: ultraskeleton (16, past Gilead), shimmer (8, Gilead's flats), megawraith (21, of
	Gilead), dark bear (24) and necromancer (26) (past Gilead), ogre (23, east of Gilead), beast (23)
	and horror (27) (near Gilead), fear (23, "to Endworld" and "from Gilead").
- Near Endworld and Kalle again, in the high levels: lycanthra (30) and terror (31) (near Endworld),
	silver slime (30, under Endworld and near Gilead), wyvern and lesser wyvern (33, 32, between Bris
	and Kalle), armor knight (33, east of Kalle), pale knight and blue dragon (39, above Kalle), liche
	king (44, under Kalle), insurgent (46, above Kalle), incubus and succubus (44, 47, inns near
	Narcissa and Hambry), demon (45, near Narcissa), shadow dragon (44, outside Narcissa).
- The Liche King's and the Dead School's places stay as written in `monsters/undead.md`, as courts
	told of. The other 40s and 50s "past" or "beyond" a far town stand.

### The review's decisions (cross-chunk)

- **Lightning at Kalle.** `towns/kalle.md` and `world/weather-and-time.md` put lightning "on the open
	ground" at Kalle, as do the lore of the Spark Ring and talk of Kalle's wire men. The weather
	(`app/lib/weather.lua`) sends every storm from within 30 tiles of Midworld toward Gilead, 140 tiles
	from Kalle on the other side, so the edge of the widest storm never comes within about 70 tiles of
	Kalle, and Kalle's own sky holds only fog, heat, drizzle, cloud, sun and clear: no storm, thunder
	or lightning ever reaches Kalle or the Diggings, and the Diggings snow only on its peaks. The
	mechanics win; the lore stands as the trade of Kalle's wire men and charm-sellers, who take their
	rings out to the storm road to the north-west. Fixed in the chunks (`towns/kalle.md`,
	`world/weather-and-time.md`, `peoples/trades.md`, `lands/diggings.md`). The Storm Charm's "Kalle
	sellers say the crystal hums louder when a strike is close" stands as a seller's saying.
	fix: `app/content/items/spark_ring.lua`: "wear them out on the open ground" to "on the storm road".
- **Dry country by Bris.** `towns/bris.md` said the dry country lies south-east of Bris; south-east of
	Bris on the map is the Midlands. The Dry Country's tracts lie west of Bris (latitude -60 to 95,
	longitude -250 to -155) and north-east of it (latitude 125 to 250, longitude -35 to 55): the map
	wins; `towns/bris.md` now says "to the west and the north-east".
- **The corner of the map.** `world/overview.md` said the lakes and peaks near the south-west corner
	stand for the far side of the edge. The data shows no lake and one peak within 75 tiles of
	Endworld (35 hill cells, 65 Ashland cells and 128 Dry Country cells); the big lakes of the south
	and west edges lie far from the corner: the data wins. What lies "beyond Endworld" (sea-coast,
	lake, mountains, demon stronghold) is the far side of the edge and is not drawn; the chunk now
	says so. This replaces the earlier inference that the lakes and peaks near the corner stand for it.
- **One Mages' guild.** The lore says "the Mages' guild in Roma", "the Mage's guild" that buys every
	thornwood root, "the mage guild" that buys magic stones in bulk and "Mages' guilds" that sell ward
	charms. No second guild is named: they are one body, seated in Roma, and the chunks write "the
	Mages' guild". Narcissa's college is a school, not a guild (`towns/roma.md`, `towns/narcissa.md`).
- **The storms' road and the storm road** are one name, and the south-east arm (Kalle) lies behind it.
- **The ice pits and the pits.** Kalle's ice pits (winter ice, frost charms) are not the devils' pits
	(under the old mines and under Hambry); the fire pits of Hambry are part of the devils' country.
- **Homes of names.** The Order and the oath book are in `magic/paladins.md` (the chapel itself, in
	`towns/midworld.md`); the lamplighters' guild is in `peoples/trades.md`; the hall of the pleaders is
	in `towns/hambry.md` (the four who sit in it, in `monsters/people.md`); the keg trick is in
	`monsters/people.md` (the numbers, in `things/battlefield-objects.md`); the crown is in
	`legends/upper-echelon.md`. Each is one glossary line.

### Fixes to the game's lore

Each of these lore fields contradicted the game's mechanics; only the `lore` was edited.

- fix: `app/content/spells/fire_ward.lua`: "the apothecaries of Midworld sell a draught" to "of Bris".
	Midworld sells no ward draught (`app/sql/seed.sql`); the Fire Ward Draught starts at Bris.
- fix: `app/content/spells/storm_ward.lua`: "Traders in Bris sell a draught" to "Traders in Kalle".
	Bris sells Fire and Frost Ward Draughts only; the Storm Ward Draught starts at Kalle.
- fix: `app/content/items/antidote.lua`: "in every town" to "in every town from Midworld to Kalle".
	Only Midworld, Roma, Bris and Kalle sell it; Narcissa and on sell Cure-All instead.
- fix: `app/content/items/viper_charm.lua`: "Narcissa's apothecaries will not sell one without a tin
	of Antidote" to "Kalle's apothecaries": Narcissa sells no Antidote.
- fix: `app/content/fields/rain.lua`: "most farmers in the south" to "most farmers there". Roma and
	Bris lie north of Midworld (latitude 30 and 70).
- fix: `app/content/monsters/fire_wyrm.lua`: "the hills south of Endworld" to "near Endworld". Endworld
	is at latitude -250, the edge, and nothing lies south of it. Other "beyond Endworld" places are the
	far side of the edge, not tiles of the map, and stand.
- fix: `app/content/spells/venom.lua`: "Paladins call it a sin" to "Warriors call it a sin". No Paladin
	learns Venom (the Mage learns it at 33, the Warrior at 82); `magic/paladins.md` says so.
- fix: `app/content/items/spark_ring.lua`: see "Lightning at Kalle".

### Other decisions

- The Demon King's lore says he has ruled "since before the first town was founded at Midworld" and the
	Greatest Devil's that it is "the one the others obey": two rulers; both stand. The Greatest Devil heads
	the devils' ranks (fiend to greatest devil) and those that "came up through the cracks in the old
	roads"; the Demon King rules the demons' realm (Prince, Lord, soldiers) and the Dark Daemon "serves"
	him; their relation is left unsaid (`monsters/demons.md`).
- The Liche King's court is "in the crypts under Kalle" (with his steward the Liche Lord) and the Liche
	Master and Liche Prince run "the dead school beyond Narcissa": two courts, both stand; the Liche
	Prince rules the school "above its Master" and no file makes him the King's or his rival
	(`monsters/undead.md`).
- The pleaders of Hambry: the Advocate is "the first of the four pleaders of the hall", the Fanatic,
	Zealot and Obsessive his followers: four in the hall; the Demagogue is a separate speaker in Gilead
	(`monsters/people.md`, `towns/hambry.md`).
- The Dawkin is "what a Dawk becomes" (21) and the Dawkor "the first of the dawkor kin... still the
	smallest" (26), the Dawkare "the grown kin of the dawkor" (29): two lines, the cave and mine gangs
	(Dawk, Dawkin) and the pass packs (Dawkor, Dawkare) (`monsters/giants.md`).
- The Serafiend is "a seraph that fell out of the choir" while the Seraph's set is dropped by "seraphs
	... slain" in the high passes beyond Gilead: seraphs are a kind of being of which the Serafiend and
	Lucifuge are fallen; no seraph and no angel is a monster in the game; both sets are told of
	(`monsters/demons.md`, `things/legendary-sets.md`).
- The Golem spell's lore says it is "built from river stone" and the summon's that it is raised from "the
	old foundations of a broken chapel" and "quarried stone": the chapel's foundations are river stone,
	quarried (`magic/allies.md`).
- The Bear summon comes from "the woods north of Midworld" and Call Bear says "the hills above Roma": Roma
	lies north-east of Midworld, so it is one country (`magic/allies.md`).
- The fire pits are "under Hambry" (hellbeast) and "beyond Hambry" (hellion) and the devils' pits "under the
	old mines" and "below the mines": one country of pits, running under Hambry and the mines outward, where
	devils keep ledgers and a cult keeps hellbeasts (`towns/hambry.md`, `monsters/demons.md`,
	`monsters/beasts.md`).
- A drop is chosen by the level of the monster (`drop_level`, "monsters of this level and up", 1 in 30
	victories), not by kind; the drops' lore names a source ("a guardian that fell near Roma", "a young dragon
	on the cliffs above Bris"): the mechanic wins and the lore is where the first was found
	(`world/overview.md`, `legends/upper-echelon.md`). `app/content/items/angels_joy.lua` names Roma (ring 30,
	levels 5 to 7) for a drop level of 25; left as it is (see Open). The "young dragon" of the level-10
	Dragon's Claw and Scale is read as a drake kin.
- The Destiny Blade is "forged in Midworld from a fallen star" and the Starsteel Sword's iron "comes from a
	meteor that fell on the Endworld plain": two falls, both stand. The Destiny gear is "rarely for sale" yet
	only Endworld's shop sells it: both stand (forged at the start of the road, sold at the end)
	(`legends/upper-echelon.md`).
- Lore speaks of winters, springs, autumns and "every season of high winds" while the clock has a two-hour
	day and no seasons: both stand; nothing in the mechanics is tied to a season
	(`world/weather-and-time.md`).
- The weather plan (`docs/plans/elements-and-weather.md` section 3) said a storm slot every 20 minutes forming
	3 times in 5, then section 7 "a slot every 45 minutes, forming 45% of the time"; `app/lib/weather.lua` has
	SLOT 2700 and FORMS 0.45: the code wins (about one storm in 100 minutes); the plan's section 3 was fixed.
- Fog comes off Narcissa's low ground (`fields/fog.lua`) and off the Hambry marsh (`spells/fog_bank.lua`):
	both stand; the Greymoor is foggiest (dawn about half), the Weald and the Thornbog fog too.
- Midworld, Bris and Kalle lie on one line, as do Narcissa, Midworld and Hambry, so "the road between Bris
	and Kalle" and "between Narcissa and Hambry" would run through Midworld: the map wins, and "between X and
	Y" is read as the country between their lands, off the hub (`world/overview.md`, `lands/dry-country.md`).
- The old "between Bris and Kalle" dry road (hellhound 20, lesser wyvern 32, wyvern 33, water cactus,
	nomad's band): a road from Bris (ring 70) to Kalle (ring 100) through the hub meets levels 1 to 21; level
	wins (see "Where monsters live"), and the place is read loosely: the west tract by Bris and the east tract
	north of Kalle (`lands/dry-country.md`).
- The dry road south of Roma and the marshes past Roma (scorpion, rogue scorpion, illusion): only 2 cells of
	Dry Country lie within 75 tiles of Roma and the nearest Thornbog tract is east, along longitude 160 to
	250: the lore stands as strays that came up the caravan tracks, and the marsh mists "past Roma" as the
	Thornbog's east tract (`lands/copper-downs.md`).
- Thornwood grows "in the bog below Kalle" (`thornwood_bark`) and is carved by the bog priests of Gilead:
	both stand; the Thornbog has four tracts, near both towns (`towns/kalle.md`, `towns/gilead.md`).
- "Past Gilead" and "beyond Gilead" are the last 50 tiles of the north-west corner, the Storm Barrens
	(Gilead is at latitude 200 and the map ends at 250) (`lands/storm-barrens.md`).
- Hambry is called a "city" in the Greatsword's lore: it stands as the biggest of the towns
	(`towns/hambry.md`).
- The Shoals' "tide line", tidal flats and sea mist, with no sea on the map (plan decision 4): both stand; the tide line is the edge of the flats' wet sand and the open sea is told of, not drawn
	(`lands/salt-shoals.md`).
- Woods outside the Weald (dark wolves "past Kalle", werebears "between Kalle and Narcissa", "the woods north of
	Midworld", "the deep woods past Gilead"): the Woods field belongs to the Weald alone; those woods stand as
	timber on slopes within other lands, and fights there are on the land's own ground (`lands/diggings.md`,
	`lands/midlands.md`).
- Rivers ("river gravel near Narcissa", "river marshes near Hambry", "river reed", "river stone"): no river
	is drawn and none can be; rivers are streams too small for the map between the lakes (`lands/greymoor.md`,
	`lands/hambry-weald.md`).
- Hambry's "high pastures", "grey hills" and "bare ridges" against a Weald that is all forest: Hambry's
	neighbourhood holds five patches of the Greymoor (295 Greymoor cells within 75 tiles of the town against 339
	of Weald); those are the pastures, hills and ridges (`lands/hambry-weald.md`, `lands/greymoor.md`).
- Creatures named by item lore that have no monster file (rats, "wisps and bats", a swamp tortoise "nearly as
	big as a cart", a marsh hornet, cave bears, ice wolves, "young dragons"): told of, not met; the land chunks
	name them as told, never as roaming monsters.
- The Explosive Barrel is sold in Kalle, Narcissa and Gilead but appears by itself only in the Diggings; the
	Weald's `forest` field alone makes a beehive likelier; the Midlands and Midworld's 12 tiles have no objects
	(`things/battlefield-objects.md`).
- The Thornwood set's descriptions say "Worn with the rest of the Thornwood set" but there is no set bonus and
	only three accessory slots for four pieces: the set is four accessories whose costs partly cancel; no
	mechanic is invented (`things/legendary-sets.md`).
- The inn prices (5 to 125) and the road order live in `world/overview.md`; `peoples/roads-and-outlaws.md`
	points to them. `monsters/others.md` states the ring rule and links to the formula in `world/overview.md`.

### Inferred facts

- The old kingdom's roads, garrisons and crown run out from Midworld, the first town; the lore says only "the
	first town was founded at Midworld", "the road out of Midworld" and "the old kingdom"
	(`world/overview.md`, `towns/midworld.md`).
- The crown named by the Demagogue, the Insurgent, the Renegade and the Dark Knights, and the "old kingdom" of
	the Liche King, are one crown (`legends/upper-echelon.md`).
- The four arms of the world, each with a character of its own, are a reading of the two town lines and their
	lands, not a statement in the lore (`world/overview.md`).
- "Above" a place (the passes above Kalle, the chapels above Roma) means higher ground there, not north
	(`world/overview.md`).
- Midworld is where characters begin (a new character's place is 0, 0 and "In Town", `app/sql/schema.sql`),
	and the old walls named in the Shadow's lore are Midworld's own (`towns/midworld.md`).
- Narcissa's college is where "the mages of Narcissa" make Hi-Ether (`towns/narcissa.md`).
- The temple of Hambry, the abbey and the watch guild are three bodies, and Gilead's "temple smiths" and
	"shrine" are one temple (`towns/hambry.md`, `towns/gilead.md`).
- The storms' road passes over Bris and the Storm Barrens, by geometry, within the storm's wobble of about 4
	degrees (`world/weather-and-time.md`).
- The legs of the road order and their straight-line lengths are computed from the towns' coordinates
	(`world/overview.md`).
- The dragons table's "lair" and "breath" columns are the lore's and the monsters' spell lists set side by side
	(`legends/upper-echelon.md`).
- The lands' tracts, shares, features and level spreads quoted in the land chunks are read from
	`app/lib/terrain/world.lua` by counting (cells of 5 x 5 tiles, rows from the north) and are facts of the map,
	not of the lore (the `lands/` chunks).
- The Dry Country tracts west of Bris and north of Kalle stand for the lore's "between Bris and Kalle"
	(`lands/dry-country.md`).
- The Thornbog's east tract is "the marshes near Kalle", its south tract "the bog below Kalle", its north-west
	tract Gilead's "thornwood bog" and "the marshes beyond Gilead" (`lands/thornbog.md`).
- The Weald's lakes and ponds are the "deep pools below Hambry" (`lands/hambry-weald.md`).
- The pits of the devils "under the old mines" lie under the Diggings, since Kalle is the mining town
	(`lands/diggings.md`).
- Kalle's "wooded slopes" and "forest road" are timber, not the Weald (`lands/diggings.md`).
- The scorched ground near Narcissa (Fira Elemental) and the "scorched hills" (Fire Raven) are the foundries'
	slag fields (`lands/greymoor.md`).
- The pearl "shell beds" south of Bris are the Shoals' tidal flats south of the town (`lands/salt-shoals.md`).
- The garrisons that turn bandit when unpaid (Renegade, Traitor, Phantom) answer to the crown; "unpaid
	garrisons turn" is a reading of three monsters (`peoples/roads-and-outlaws.md`).
- The Hambry road, the Narcissa road and the others named as roads are read by the towns they join; no road
	is drawn on the map (`peoples/roads-and-outlaws.md`).
- The "young dragons" of Dragon's Claw (cliffs above Bris) and Dragon's Scale (cliffs near Kalle) are drake
	kin, since no dragon of a level that drops at 10 exists (`monsters/drakes-and-dragons.md`).
- The Dead School and the King's crypts are two courts with no rank between the Liche Prince and the Liche King
	(`monsters/undead.md`).
- The devils' ranks run Fiend, Lesser Devil, Devil, Greater Devil, Greatest Devil, with the Cherufiends at the
	stairs and the Archfiend and Lucifuge outside the ladder, by the lore's own words "lowest", "a step above",
	"middle ranks", "senior" (`monsters/demons.md`).
- The Paladins' "chapel" in the Sunshine field's lore is the Midworld chapel (`magic/paladins.md`).
- Seraphs and winged guardians are beings told of and not met: no monster is named for either
	(`things/legendary-sets.md`, `monsters/demons.md`).
- The rats, bats and wisps that leave the Life and Magic Pebbles are told of and not met
	(`things/legendary-sets.md`).
- No monster uses the ally spells: the files switch Call Bear and Call Spirit off for the monsters that would
	inherit them (`magic/allies.md`).
- Call Wolf is learned by no class and used by no monster or item (`magic/allies.md`).
- "Regen", "Poison", the four breaths, Doom, Deluge, Heavy Blow, Hyper Beam, Knock Over, Brimstone, Miasma,
	Nightfall, Fog Bank, Solar Beam, Thunderbolt and Water Jet are monster or item spells that no class learns
	(`magic/mages.md`, `magic/elements.md`).
- The lycans' weakness to holy light is "silver" in the old tongue (the `werewolf` file's comment): silver
	stands for holy for every lycan and the dead (`monsters/beasts.md`).
- The nisse "out onto the roads" means the Nisse roams where the others of its kind stay in barns; no mechanic
	(`monsters/fey-and-spirits.md`).
- The dead who owe (ghost, specter, spirit, dybbuk) share a motif of debt, the lore's own repetition
	(`monsters/fey-and-spirits.md`, `legends/sayings.md`).

## Open

- The Dawkor (26) is "still the smallest" of a kin whose Dawkin (21) is lower in level; the two lines read as
	separate (see Decided), but a lore edit could say so (`app/content/monsters/dawkor.lua`).
- The doomers' lore never says where the Doomer itself is met ("seen above ground"); the Megadoomer is south of
	Gilead and the Ultradoomer beneath the Hambry road (`monsters/undead.md`).
- The game has no angel or seraph monster, though two item sets come from them; a future monster could fill it
	(`things/legendary-sets.md`).
- Optional lore edits not made: `app/content/items/angels_joy.lua` places a level-25 drop near Roma (a
	Narcissa source would match its numbers); `life_pebble.lua` and `magic_pebble.lua` name rats, wisps and bats
	that are not met (the critters and scamps near Midworld are); the four Thornwood item files say "Worn with
	the rest of the Thornwood set" (they could say "pairs well with").
