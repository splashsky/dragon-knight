---
id: things/legendary-sets
summary: What monsters leave behind, from the Life Pebble to the gems, and the sets: Destiny, Dragon's, Angel's, Seraph's, Demon's and Thornwood.
related: [things/gear, things/consumables, monsters/drakes-and-dragons, monsters/demons, monsters/beasts, legends/upper-echelon, towns/endworld, lands/thornbog, magic/elements]
sources: [app/content/items/life_pebble.lua, app/content/items/magic_pebble.lua, app/content/items/dragons_claw.lua, app/content/items/dragons_scale.lua, app/content/items/dragons_tooth.lua, app/content/items/dragons_plate.lua, app/content/items/dragons_tear.lua, app/content/items/dragons_wing.lua, app/content/items/angels_joy.lua, app/content/items/angels_rise.lua, app/content/items/angels_truth.lua, app/content/items/angels_love.lua, app/content/items/seraphs_joy.lua, app/content/items/seraphs_rise.lua, app/content/items/seraphs_truth.lua, app/content/items/seraphs_love.lua, app/content/items/demons_fall.lua, app/content/items/demons_sin.lua, app/content/items/demons_hate.lua, app/content/items/demons_lie.lua, app/content/items/thornwood_bark.lua, app/content/items/thornwood_thorn.lua, app/content/items/thornwood_heart.lua, app/content/items/thornwood_root.lua, app/content/items/destiny_blade.lua, app/content/items/destiny_aegis.lua, app/content/items/destiny_raiment.lua, app/content/items/ruby.lua, app/fight/encounter.lua, continuity.md]
---

# Drops and sets

## What a monster leaves

Now and then a victory leaves an accessory: a trinket of the kind the world has always picked off its
dead. Each has a **drop level**: it can only be left by a fight against a monster of that level or
higher. So a Life Pebble comes from anything, a Ruby only from the top. The lore of a drop names a
place and a creature (a goblin camp, a fallen guardian); the place is where such things are *told
of*, and any fight of the level may leave one. Three can be worn at a time. Most are
not for sale (the resist and ward rings are, in `things/gear.md`); the pieces of a set pay for each other's costs.

## The plain drops (levels 1 to 30)

- **1**: Life Pebble (life +10; "slimes and rats leave behind near Midworld") and Magic Pebble (magic +10; apprentices
	collect them by the pocketful, wisps and bats leave them). Rats, bats and wisps are told of but not met.
- **2**: Sparrow Feather (dexterity +6; the stubble fields outside Midworld after harvest; boys who want to be runners).
- **4**: Wolf Fang (attack +10; strung by the door on the Midworld road).
- **5**: Fortune Drop (gold +10%; a holed copper coin dropped by cutpurses near Midworld), Memory Drop (experience
	+10%; scholars in Roma pay to take them off monsters), the Serpent Ring.
- **7**: Tinker's Buckle (defense +10; a Roma tinker's leftovers, found on goblins).
- **8, 12, 15**: Ember Ring, Rime Ring, Spark Ring (resist rings, `things/gear.md`).
- **10**: Life Stone (life +25; under boulders on the roads around Bris), Magic Stone (magic +25; gravel of the hill roads
	around Roma, bought in bulk for the guild), Dragon's Claw and Scale.
- **16**: Nomad's Band (travel points +30; the caravan folk who cross the dry country between Bris and Kalle).
- **18**: Tortoise Shell (defense +35; swamp tortoises as big as carts; Bris fishermen).
- **20**: Hornet Sting (attack +35; marsh hornets east of Bris).
- **22**: Hawk Eye (dexterity +30; a lens from a trader of Hambry).
- **24**: Frost Fang (casts Frostbite free, six charges; ice wolves on the high passes past Narcissa; they rarely come down).
- **25**: Life Rock (life +50; goblin camps in the hills past Roma), Magic Rock (magic +50; the ruined shrines past Kalle).
- **28**: Bard's Pipe (travel points +30, dexterity -10; minstrels at Hambry's inns).
- **30**: Sage's Lens (experience +25, life -20; a monk in the hills above Hambry grinds them; cracked ones are left by monsters).
- **40, 45, 48**: Vulture Plume (dexterity +120, life -50; the carrion birds of the battlefields past Gilead), Bearclaw
	Totem (casts Warlord twice and is used up; the clans above Endworld), Shepherd's Lamp (casts Gaia, three
	charges; the shepherds of the valleys beyond Endworld).
- **50**: the **gems**, from the top monsters only: Ruby (life +150; old mines near Kalle), Emerald (strength +150; deep
	workings past Hambry), Obsidian (attack +150; cooling fields beyond Endworld), Diamond (defense +150; Gilead's smiths pay
	for them), Topaz (dexterity +150; river gravel near Narcissa), Pearl (magic +150; the tidal shoals south of Bris).

## The Dragon's set (levels 10, 30, 35)

Pieces of dragons, told of by hunters and armorers. Six, in pairs: attack and defense, then strength and dexterity.

- **Claw** (10; attack +25): from "a young dragon on the cliffs above Bris", filed sharp and set in silver.
- **Scale** (10; defense +25): shed by a young dragon on the cliffs near Kalle; armorers pay well.
- **Tooth** (30; attack +50): pried from a dragon's jaw by a hunting party out of Narcissa that did not all come home.
- **Plate** (30; defense +50): from an adult dragon's belly on the scorched road past Hambry; Warriors in Gilead have it set
	into breastplates.
- **Tear** (35; strength +50): "a clear lump of dragon bile hardened over years in a lair"; Endworld's priests sell it at a high price.
- **Wing** (35; dexterity +50): a torn membrane from a dragon brought down over the marshes beyond Gilead.

The young dragons of the level-10 pieces are the drake kin (`monsters/drakes-and-dragons.md`); the great
dragons are met much further out.

## The Angel's set (levels 25, 30, 35, 40)

Dropped by **winged guardians** (angels) when they fall: life and strength together, in rising pairs.
- **Joy** (25; +25 each): a white feather near Roma; the priests sell the one feather left over.
- **Rise** (30; +50): a golden feather in the hills past Hambry; wardens in Hambry tie them to their helms.
- **Truth** (35; +75): a crystal lens, cloudy until a true word is spoken; the judges of Narcissa keep a box of them for
	disputes.
- **Love** (40; +100): a pale ring of light-metal from a guardian that fell to a hunting party out of Bris; it warms the hand
	of anyone who has done a kind thing that week. Mages in Kalle call it a fraud and wear it under their robes.

## The Seraph's set (levels 25, 30, 35, 40)

Dropped by **seraphs**, the fire-winged: magic and dexterity together, same pairs. Mages and archmages value them.
- **Joy** (25; +25): a fiery ember from a wing, slain in the high passes beyond Gilead; smells of cinnamon.
- **Rise** (30; +50): a plume of ember-red feather that does not burn, shed over the ash plains.
- **Truth** (35; +75): a lens of gold glass that shows a spell's true shape; archmages lock them in iron boxes.
- **Love** (40; +100): a ring of smoke-gold with a white stone, from the fire-lit halls under Endworld.

Seraphs also fall: the Serafiend and Lucifuge are of the fallen kind (`monsters/demons.md`).

## The Demon's set (levels 35, 45)

Demon trophies: strength paid for with the body. Each pair costs life or magic.
- **Fall** (35; strength +50, magic -50): a cracked horn tip from a demon that fell from the walls of Gilead.
- **Sin** (35; strength +50, life -50): a black medallion with a face no two wearers describe alike; from the ruins past Gilead.
- **Hate** (45; strength +100, magic -100): a black iron ring with a red thread, from a demon out of the cellars of Endworld.
- **Lie** (45; strength +100, life -100): a forked tongue of hardened ash, from a demon who spoke in a merchant's voice outside Hambry.

Warriors take Fall and Hate; Mages find their spells "come out thin and bitter".

## The Thornwood set (levels 20, 26, 32, 38)

Four accessories cut from the thornwood that grows in the bog below Kalle, "where the trees put out spines to keep the bears
off" (`lands/thornbog.md`). Each gives and takes, and worn together the pieces pay for one another:
- **Bark** (20; defense +40, magic -25): stops a club; Mages dislike it.
- **Thorn** (26; attack +55, life -40): the longest spines, from near the top where bears cannot reach.
- **Heart** (32; life +90, dexterity -10): the hard red knot at the root of trees three hundred years old; bog priests in
	Gilead carve them.
- **Root** (38; magic +100, defense -15): roots that run a mile under the bog; the Mages' guild buys every one.

Bark with Root, or Thorn with Heart, makes a pair that mostly pays its own cost. There are four pieces and three slots.

## The Destiny set (sold at Endworld)

Not dropped: made. Three pieces, rarely for sale ("buyers have to be known to the smiths"), all of the upper echelon
(`legends/upper-echelon.md`):
- **Destiny Blade** (attack 250, strength +50): "forged in Midworld from a fallen star"; its edge has never needed
	sharpening.
- **Destiny Aegis** (defense 100, life +50): a shield of pale metal with a rim of gold, "carried by the first knight to hold the
	road out of Midworld"; its face is never scratched.
- **Destiny Raiment** (defense 200, dexterity +50): the robe of the set, grey silk that shifts colour; woven for someone else first.

All three are sold in Endworld, at the far end of the road (`towns/endworld.md`).
