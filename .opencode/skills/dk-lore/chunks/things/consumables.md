---
id: things/consumables
summary: The things a traveller drinks, eats and throws: herbs to elixirs, draughts and tonics, flasks and dusts, who brews them and where they are sold.
related: [things/gear, things/legendary-sets, magic/afflictions, magic/elements, peoples/trades, monsters/people, things/battlefield-objects, towns/kalle, towns/bris, towns/narcissa, towns/hambry, towns/gilead]
sources: [app/content/items/herb.lua, app/content/items/potion.lua, app/content/items/hi_potion.lua, app/content/items/elixir.lua, app/content/items/cure_all.lua, app/content/items/trail_snack.lua, app/content/items/travel_tea.lua, app/content/items/regen_potion.lua, app/content/items/bitter_draught.lua, app/content/items/ether.lua, app/content/items/hi_ether.lua, app/content/items/antidote.lua, app/content/items/fire_ward_draught.lua, app/content/items/frost_ward_draught.lua, app/content/items/storm_ward_draught.lua, app/content/items/guard_tonic.lua, app/content/items/strength_tonic.lua, app/content/items/fire_flask.lua, app/content/items/acid_vial.lua, app/content/items/sleep_powder.lua, app/content/items/weakening_dust.lua, app/content/items/void_flask.lua, app/content/items/explosive_barrel.lua, app/content/items/war_standard.lua, app/sql/seed.sql]
---

# Consumables

Used up when used, in a fight or out of it. Every town sells Herbs; the rest follow the road.
Prices are in gold; the town lists are in `app/sql/seed.sql`.

## To mend

- **Herb** (15; everywhere). A bitter green leaf that grows wild along the roads around Midworld;
	travellers chew it on the march. 30 hit points. "It tastes terrible and works every time."
- **Trail Snack** (20; Midworld, Roma, Bris). Oats, dried fruit and something sweet, packed in wax
	paper by market bakers; farmers' children eat them on the walk to the fields. 15 hit points and
	10 travel points.
- **Travel Tea** (25; Midworld to Kalle). Mint and bark, brewed in tin pots at the market stalls.
	30 travel points; drink it in town. An innkeeper in Bris once said it was "the only thing he had ever sold that people came back for".
- **Potion** (60; Roma to Endworld). A red draught in a stoppered bottle, brewed by apothecaries
	in every town; the good ones seal the cork with wax. 100 hit points.
- **Hi-Potion** (180; Bris, Kalle, Narcissa, Hambry). Deep amber, from the big apothecary in Bris who sells to
	caravan guards a dozen at a time and makes them sign for each bottle. 250 hit points.
- **Elixir** (900; Gilead, Endworld). Gold-flecked, made in a single workshop in Gilead by a family
	who will not let anyone into the cellar; the price is painted over the motto. 400 hit points and
	60 magic.
- **Cure-All** (350; Narcissa to Endworld). A dark green syrup from the abbey cellars in Hambry, first made
	for the monks who came back from the marsh with blood poisoning. Cures every harmful effect and gives
	40 hit points; the abbey says it costs a week's wages because it works on everything.
- **Regen Potion** (100; Bris, Kalle). A green syrup mages in the border towns sell to travellers who
	expect to be hurt: wounds knit a little with every step.
- **Bitter Draught** (160; Narcissa, Hambry, Gilead). Wormwood and something the healers will not name,
	from Narcissa's old infirmary's wide clay jug. So bitter most drink it once and carry it for life.
	Heals slowly and steadily.
- **Antidote** (30; Midworld to Kalle). A bitter brown tincture in small green bottles. Cures poison,
	sleeping draughts and most of what comes off bog creatures. Nothing for wounds.

## For magic

- **Ether** (80; Roma to Endworld). Faintly blue, distilled by mages who run dry mid-fight. 30 magic
	points. Most mages carry three before going into the hills.
- **Hi-Ether** (300; Narcissa, Hambry, Gilead). A cold blue distillate made by the mages of Narcissa in
	copper stills on the north wall of the college (the smell set off too many fires in the old
	lodgings). Each flask carries its maker's name, and the college refuses a sale to strangers.
	100 magic points. Court mages use it in the second hour of a long fight.

## Draughts and tonics

- **Fire, Frost and Storm Ward Draughts** (240 each). The ward spells in a bottle, for those who have not
	yet learned them: half the damage of the element for eighty seconds (`magic/afflictions.md`).
	- Fire (Bris to Endworld): pale yellow; the apothecaries brew a few dozen at a time and sell out
		in the week, and prefer nobody ask what goes into it.
	- Frost (Bris to Hambry): blue, tasting of snow water and tallow. Trappers take three before a
		winter crossing and come back with two.
	- Storm (Kalle to Gilead): grey, smelling of wet slate; Kalle's apothecaries say it is the Storm
		Charm's crystal ground fine. Gilead's wardens carry a flask on every watch.
- **Guard Tonic** (240; Narcissa, Hambry, Gilead). Grey, oily, tallow and boiled bark; the Narcissa gate
	guards drink it before a night watch. Takes a quarter less damage for the fight.
- **Strength Tonic** (240; Kalle, Narcissa, Hambry). Ginger and black pepper in a thimble cup; the pit
	master of Kalle sells it at cost to gladiators because a dull fight pays him less. A quarter more damage
	for the fight.

## To throw

- **Fire Flask** (50; Roma to Narcissa). Lamp oil in a clay flask with a rag in the neck, from the lamplighters' guild in Roma. Light it, throw it; the
	oil keeps burning on the hide. Throw it before the thing can step on your feet. Monsters throw it too, at kegs.
- **Acid Vial** (120; Bris, Kalle, Narcissa). Thick green acid, sold by a chemist in Bris who wears gloves to the
	market and will not say where it comes from; smells of wet pennies; sailors buy it for barnacles.
- **Sleep Powder** (45; Roma, Bris, Kalle). Poppy heads and a root the herbwives keep in unlabelled tins. Throw it
	upwind (the guards in Roma learned it the hard way).
- **Weakening Dust** (200; Kalle, Narcissa, Hambry). Salt-pan powder from the mouth of the Kalle road and a
	bitter white root the pan-men dig at night. A soldier in Kalle says it is "the only thing" he has seen that makes an ogre hesitate.
- **Void Flask** (1500; Gilead, Endworld). Black glass blown in Gilead from sand the miners bring up from below
	the salt marsh. The shards pull the light off the monster and keep it. Mercenaries in Endworld pay by
	weight; the glassblowers keep the receipts in a locked box.
- **Explosive Barrel** (180; Kalle, Narcissa, Gilead). Blasting powder by the keg, for Kalle's miners and anyone who has
	the gold and no wish to be asked why. Keep it dry and away from the cook fire; fire or lightning lights it, water
	douses it, and it blasts everyone, you too (`things/battlefield-objects.md`).

## Not for sale

- **War Standard.** Nobody sells one. The knights of the old garrisons carry one folded in the saddlebag and raise it
	on the first turn; everyone on their side deals a quarter more damage while it stands, and the first
	good blow brings it down (`monsters/people.md`).
