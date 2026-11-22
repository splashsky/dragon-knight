---
id: towns/midworld
summary: Midworld, the hub town where every character begins: its market, its towers and chapel, the quiet Midlands round it, and where the storms are born.
related: [world/overview, world/weather-and-time, lands/midlands, towns/roma, peoples/trades, peoples/roads-and-outlaws, monsters/slimes, legends/upper-echelon, legends/sayings]
sources: [app/sql/seed.sql, app/content/classes/mage.lua, app/content/classes/warrior.lua, app/content/classes/paladin.lua, app/content/items/stick.lua, app/content/items/club.lua, app/content/items/branch.lua, app/content/items/clothes.lua, app/content/items/leather_armor.lua, app/content/items/wand.lua, app/content/items/copper_ring.lua, app/content/items/herb.lua, app/content/items/sparrow_feather.lua, app/content/items/fortune_drop.lua, app/content/items/wolf_fang.lua, app/content/spells/cleave.lua, app/content/spells/dawn.lua, app/content/spells/gust.lua, app/content/spells/torrent.lua, app/content/spells/revive.lua, app/content/spells/sleep.lua, app/content/spells/ward.lua, app/content/spells/rockfall.lua, app/content/fields/consecrated.lua, app/content/fields/sun.lua, app/content/monsters/blue_slime.lua, app/content/monsters/critter.lua, app/content/monsters/shadow.lua, app/content/monsters/wizard.lua, app/content/statuses/poison.lua, app/lib/terrain_lines.lua, continuity.md]
---

# Midworld

## Where it is

At 0, 0: the hub, the middle of the map. Both lines of the cross run through it, so every other
town is a straight walk out of it, and it lies on the storms' road (`world/overview.md`,
`world/weather-and-time.md`). Every character begins here. Its land is the Midlands
(`lands/midlands.md`): soft farmland, stubble, hedgerows, scrub, woods to the north, and sun.

## What it is known for

- It is the first town: the Demon King is said to rule "since before the first town was founded at Midworld", and the
	old kingdom's roads start at its walls (`legends/upper-echelon.md`).
- It teaches. The Mages' towers are here ("the old masters still teach the words that bend the
	world"), the Warriors' training yards, and the chapel with the Paladins' oath book
	(`peoples/trades.md`).
- It is ordinary life: farms, hedges and a market. Nothing legendary lives near it, and nothing
	legendary is sold in it.

## Who lives here

- **The masters of the towers** teach the first spells: Gust and Torrent (Torrent comes with a
	warning never to cast it standing in a river), Whiteout last of all. They will tell you that
	the wild wizards "are no true mages at all".
- **The sergeants of the training yards** teach Cleave with a wooden sword and a bucket of sand.
	Young Warriors are told to learn Revive before anything else, and the guards on the road out
	are taught Ward before they are given a spear.
- **The chapel** keeps the oath book: the prayer of Dawn is written in it, and a page for every
	field the Order has held (`fields/consecrated.lua`). Priests bless a grave for a few gold,
	which keeps most ghosts quiet. The Paladins say their morning prayers on its steps on a
	fine day.
- **Tailors and tanners** sell clothes by the bolt and make leather armour that new recruits are
	issued on their first day. A smith who died in the last plague year stamped the copper rings.
- **Innkeepers** say Sleep works as well on drunk customers as on monsters.
- **Apprentices** carve wands from fallen ash and fill them with sparks they cannot yet hold in
	their heads.
- **Farmers** on the Midworld road string wolf fangs by their doors. Boys collect sparrow
	feathers from the stubble after harvest to be runners; cutpurses drop fortune coins on the roads.

## The market

Inn: 5 gold. It sells only the map of Roma (25 gold). Travel here costs 0 Travel Points.

- **Weapons**: Stick, Branch, Club, Wand (the Wand is the one item with a spell: it casts
	Magic Bolt without costing MP, five charges at a time).
- **Armor**: Skivvies, Clothes, Leather Armor. **Shields**: Reed Shield, Buckler.
- **Accessory**: Copper Ring.
- **Remedies and road food**: Herb, Antidote, Trail Snack, Travel Tea.

The market sells the weapons and armour of the first fights and nothing that resists an element.
The first town to sell fire flasks, ether and potions is Roma (`towns/roma.md`).

## The land around it

The Midlands (`lands/midlands.md`) and, past them, the Copper Downs to the north-east
(`lands/copper-downs.md`). Roads run out into stubble fields, hedges and brown lanes. The
earth under Midworld is "soft", and the Mages of Hambry have made it harder to live with
(Rockfall). Woods stand to the north, where a bear can be called out of the trees
(`magic/allies.md`).

## Monsters

At the gate only level 1 is met: Blue Slime, Red Slime, Critter (`monsters/slimes.md`). A step
or two out, a Creature, Shadow or Drake (level 2: shadows follow the old walls at dusk), and
at four tiles a Raven or Scamp (level 4; ravens sit on dead trees beyond the town). Each ring
of five tiles raises the level by one (`world/overview.md`).

Lore also puts a Troll under the bridges of the old road to Roma and a Ghost on the road to
Kalle. Both are met farther out than their lore says.

## Rumours and habits

- "Storms form near Midworld and drift north-west toward Gilead in about two hours."
- Nobody in Midworld has died of a single dose of poison, only of three.
- The Mages of Midworld will not light a fire in a demon lord's brimstone, "though they admit it
	would work too well."
- The Demon King is said to have ruled "since before the first town was founded at Midworld",
	and to call every challenger "Midworld's little champion".
- The Destiny Blade was "forged in Midworld from a fallen star", and the Destiny Aegis was carried
	"by the first knight to hold the road out of Midworld". Neither is sold here; the shop that sells
	them is at the far end of the road (`towns/endworld.md`).
- Shopkeepers pay only a few coins for the grey pebbles that slimes and rats leave behind.
- No ward draughts are sold here; the first town to stock them is Bris (`towns/bris.md`).
