---
id: things/battlefield-objects
summary: The ten objects found on the battlefield (barrel, hive, gas pocket, steam vent, standing stone, dead tree, tide pool, war banner, campfire, water cactus): their lands, what folk say of them, who uses them, and the wind.
related: [lands/diggings, lands/hambry-weald, lands/thornbog, lands/ashlands, lands/greymoor, lands/salt-shoals, lands/storm-barrens, lands/copper-downs, lands/dry-country, lands/midlands, peoples/roads-and-outlaws, monsters/people, monsters/beasts, monsters/giants, monsters/elementals, things/consumables, magic/elements]
sources: [docs/plans/interactables.md, app/content/interactables/explosive_barrel.lua, app/content/interactables/beehive.lua, app/content/interactables/gas_pocket.lua, app/content/interactables/steam_vent.lua, app/content/interactables/standing_stone.lua, app/content/interactables/dead_tree.lua, app/content/interactables/tide_pool.lua, app/content/interactables/war_banner.lua, app/content/interactables/campfire.lua, app/content/interactables/water_cactus.lua, app/content/items/explosive_barrel.lua, app/content/items/war_standard.lua, app/content/statuses/fuse.lua, app/content/statuses/swarm.lua, app/content/statuses/soaked.lua, app/content/statuses/rallied.lua, app/content/spells/knock_over.lua, app/content/fields/gale.lua, app/community/changelog.lua]
---

# Battlefield objects

Things that stand on the field beside the fighters: they can be hit, can burn and can go off.
Ten of them belong to a land, each found where the lore says it should be; two are items. The game's
files hold the numbers and win over this chunk; this chunk holds the stories and where they are found.

## The ten

| Object | Land | Where it turns up by itself | What it is, in a line |
|---|---|---|---|
| Explosive Barrel | the Diggings (lands/diggings.md) | 7% on plain Diggings ground, not in wet air | a keg of Kalle's blasting powder: fire lights its fuse, water douses it, it blasts everyone |
| Beehive | the Weald (lands/hambry-weald.md) | 6% to 18% under trees and on hills and shallows, by day and dry | a skep in the branches: knocked down it swarms one creature; fire smokes it off |
| Gas Pocket | the Thornbog (lands/thornbog.md) | 12%, 20% in fog or at night | a swelling bubble of marsh gas: a spark flashes it, else it bursts and poisons |
| Steam Vent | the Ashlands (lands/ashlands.md) | 15% on cinders | a crack that scalds a creature every few seconds; water sets it off, earth plugs it |
| Standing Stone | the Greymoor (lands/greymoor.md) | 8%, 14% in fog | a menhir leaning over one side: toppled, it crushes and stuns that side |
| Dead Tree | Weald, Greymoor, Barrens, Thornbog | 25% in a gale; 6% on the moor and the Barrens otherwise | a snag that falls on whoever is under it, on the foe if you aim the last blow; fire lights it |
| Tide Pool | the Shoals (lands/salt-shoals.md) | 12%, and 6% in any Shallows; none in snow | a rock pool of brine: broken, it soaks the whole field |
| War Banner | the Barrens (lands/storm-barrens.md) | 8%, none in a storm or blizzard | a torn standard: its side deals more damage; a gale or a fire takes it down |
| Campfire | the Copper Downs (lands/copper-downs.md) | 10%, 18% at night; none in damp skies | a goblin camp's coals: a spark sets another object alight; water puts it out |
| Water Cactus | the Dry Country (lands/dry-country.md) | 18% under sun or heat, 12% otherwise | a cactus full of cold water: split, it heals the worst hurt; fire burns it to a husk |

At most one object appears by itself in a fight, at most three stand on the field, and none appears
anywhere in the Midlands or within 12 tiles of Midworld (see lands/midlands.md). Which one is chosen by the
fight's own hash, not by dice.

## What folk say

- **Explosive Barrel.** "Kalle's miners buy blasting powder by the keg, and they haul it up to the diggings in the
	same cart as their ropes and their bread. Each of them has a story about a keg that went off in the wrong
	place, usually next to a cook fire." A keg "does not ask who rolled it, and the one who rolled it usually
	finds out too." The sellers in Kalle, Narcissa and Gilead give one warning: keep it dry, keep it from the
	cook fire, do not roll it anywhere you would not stand yourself.
- **Beehive.** "Honey is the oldest trade in the Weald." Honey-cutters walk under the skeps each morning with a
	smoking pot on a string. Hunters say a knocked-down hive "never goes for the one who swung at it, only for
	whoever stood under it".
- **Gas Pocket.** Thornbog folk call them bog-bubbles and say the marsh breathes out through them. A torch held
	too near makes one flash blue over the reeds, "and that is how most folk learn".
- **Steam Vent.** The people of Endworld learn the hiss, which comes a turn before the scald. Some say a splash
	of water will set the whole crack off at once, "and a few fools have tried it". Endworld's masons pile rubble
	on the cracks they can reach.
- **Standing Stone.** "Nobody living knows who raised the stones." Herders keep out from under the lean. Narcissa's
	mages swear an arcane bolt will tip one over; the shepherds say a tremor will.
- **Dead Tree.** Woodcutters call them widowmakers and will not work a snag in a gale for any pay.
- **Tide Pool.** Boys throw stones at them for a bet; the fishwives of Bris call a splash the cheapest cure for a
	burning cloak.
- **War Banner.** "The war standards of Gilead go up where the men can see them." The Barrens tear more banners
	down than any enemy does, and "nobody talks about what happened next".
- **Campfire.** Goblins say a spark that lands on your boot is the fire looking for something bigger. The
	washerwomen of Roma keep a bucket by the door "and count themselves lucky when it hisses".
- **Water Cactus.** Nomads say a cactus has more sense than a well; the worst hurt gets the first of the water. "A
	cactus that burns is a waste, and the healers say so loudly."

## The items

- **Explosive Barrel** (consumable, 180 gold, sold in Kalle, Narcissa and Gilead): you roll it onto the field
	(three objects at most) and it blasts you too. The same barrel is what bandits roll.
- **War Standard**: no one sells it. The knights of the old garrisons keep one folded in the saddlebag and raise it
	on the first turn; "a knight who has lost his banner fights like a man who has lost his temper".

## Who uses them

- Barrels: Bandit, Bandit Captain, Goblin, Insurgent, Renegade, Rogue, Scoundrel and Traitor roll one onto the
	field on their second turn and light it from the third, never in damp air and never when you could not take two
	blasts (peoples/roads-and-outlaws.md, monsters/people.md). They say so first ("Stand clear, lads. Light
	the rag.").
- Banners: the Knight, the Armor Knight and the Strong Knight raise a war banner on their first turn.
- Hives: the Grey Bear, the Dark Bear and the Werebear rake one down over your head.
- Stones and dead trees: the Troll, the Ogre, the Giant and the Titan topple them onto you once a round has
	passed and only when the fall would not finish you (the spell Knock Over; monsters/giants.md).
- The Bog Witch bursts a gas pocket with her broom while you are not poisoned; the Aqua Elemental quenches a
	steam vent on you while you are healthy (monsters/elementals.md).

## Wind and fire

Each field has a wind from 0 (calm) to 3 (a gale). The thunderstorm, the blizzard and the Mage's Gale are 3;
High Peaks 2; hills, sand and cinders 1; the rest 0. A fire spreads to a barrel or a dead tree in a wind (10%, 25%
or 50% a tick for wind 1, 2, 3), never in the wet; a gale topples dead trees and tears banners. The Gale
"takes the sky's place, brings no rain, and fans a fire without putting it out": "Mages of Hambry say it is the only
part of the weather a man can hire". Storms put fires out (see world/weather-and-time.md).

## The statuses

- **Lit Fuse**: a rag fuse soaked in tallow; "miners light them with a taper and count under their breath". Water puts
	it out.
- **Swarmed**: bees in the hair and down the collar, one sting a turn; "a torch waved in the face drives them off, and
	so does a gale".
- **Soaked**: wet through; "a wet man is hard to burn and easy to shock", say the fishermen of the Shoals.
- **Rallied**: "the shout that goes down the line when a standard goes up"; it lingers a moment after the banner falls.

## Spells that touch them

Area spells (Rockfall, Starfall, Whiteout, Inferno, the dragons' breaths, Deluge, Hail, Cyclone, Whirlwind, Radiance)
strike every foe and every object; burning lights a barrel. See magic/elements.md.
