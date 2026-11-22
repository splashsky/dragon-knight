---
id: things/gear
summary: The weapon, armor, shield and charm ladders from a Midworld stick to Endworld steel: who makes each rung, where it is sold, what it costs the wearer.
related: [things/legendary-sets, things/consumables, magic/mages, magic/warriors, magic/paladins, magic/elements, peoples/trades, towns/endworld, towns/gilead, towns/narcissa, towns/hambry, towns/kalle]
sources: [app/sql/seed.sql, app/content/items/stick.lua, app/content/items/club.lua, app/content/items/axe.lua, app/content/items/broadsword.lua, app/content/items/claymore.lua, app/content/items/dark_sword.lua, app/content/items/bright_sword.lua, app/content/items/magic_sword.lua, app/content/items/glass_blade.lua, app/content/items/starsteel_sword.lua, app/content/items/leather_armor.lua, app/content/items/chain_mail.lua, app/content/items/iron_plate.lua, app/content/items/sunsteel_mail.lua, app/content/items/buckler.lua, app/content/items/large_shield.lua, app/content/items/tower_shield.lua, app/content/items/dragonhide_shield.lua, app/content/items/wand.lua, app/content/items/dawn_mace.lua, app/content/items/storm_lance.lua, app/content/items/vigil_cuirass.lua, app/content/items/ward_shield.lua, app/content/items/ward_charm.lua, app/content/items/ember_ring.lua, app/content/items/halo_charm.lua]
---

# Gear

One weapon, one armor, one shield, three accessories. Each rung of every ladder is sold a few
towns further along the road than the one before: the **attack** (weapons) or **defense**
(armor, shields) number is the rung; gold is the price. The towns' lists are in `app/sql/seed.sql`.
Drops and the sets are in `things/legendary-sets.md`.

## Weapons

- **Midworld, the first hand.** Stick 2 (10; a hedge cut), Branch 4 (30), Club 5 (40; "never hard to
	replace"): "the first weapon most adventurers carry and the last one they should keep".
- **Roma and Bris, the farmer's tools.** Sickle 7, Dagger 8 (a boot-knife for rogues), Hatchet 12 (also
	Kalle): goblins and kindling.
- **Kalle's smiths.** Axe 16, War Pick 22 (the mine captains' own, "very good at finishing a fight in a
	narrow pass"), Poleaxe 35 (gatekeepers and wolf-fighters), Battle Axe 50 (also Hambry).
- **Narcissa's foundries.** Brand 25 ("turned out by any smith who needs a quick sale"), Broadsword 45
	(soldiers' sword, a rack in every guard's armoury), Claymore 60 (hill clans forged the first), Warhammer 70 (dents plate and breaks
	a shield arm; dexterity -20), Cinder Blade 55 (quenched in brine; fire; the foundry men say it stays
	warm a week).
- **Hambry's smiths.** Greatsword 80 (for the paid guards, "open a crowd or a door with the same swing"), War Sabre 112 (for
	riders; Gilead's horse traders sell it with the saddle), Blessed Mace 70 (holy, blessed in
	the Hambry temple).
- **Gilead and the dark mines.** Dark Axe 100 (also Kalle), Dark Sword 125: black iron from the mines
	below the hills, "quenched in something the smiths will not name". They bite deep but the wielder learns slower
	(experience -5 and -10 percent). Bright Sword 100: pale steel that sings in the hand, 10 percent more
	experience. Dawn Mace 110 (holy; casts Judgement): the temple smiths forge it from the silver of a
	sunken bell.
- **The far smiths.** Magic Sword 150 (smiths and mages together; magic +50), Glass Blade 190 (unannealed
	glass, sold with a warning: maximum life -80), Starsteel Sword 215 (Endworld; iron from a meteor that fell
	on the Endworld plain before anyone lived there), Destiny Blade 250 (`things/legendary-sets.md`).

**Staves and wands** (cast a spell free of magic, a few charges, recharged at an inn): Wand (Magic Bolt;
Midworld), Spark Rod (Spark; Roma's copper workers), Frost Staff (Frostbite; Kalle: "a cave bear that has
been frosted sits down"), Ember Staff (Ember; Narcissa's fire-mages, with a cup of lamp oil on the head),
Storm Lance (Lightning Lance; Endworld's storm-watchers string the wire and hang it from a tower in spring).

## Armor

- **Cloth and leather.** Skivvies 2 (Midworld; "haggles better"), Clothes 5, Apprentice Robe 4 (Roma,
	Bris; magic +15; "the Mages' guild in Roma will tell you so at length"), Leather Armor 10 (every tanner in
	Midworld), Scout's Jerkin 12 (Roma, Bris; dexterity +8), Hard Leather Armor 25 (Bris).
- **Mail and plate of Kalle and Narcissa.** Chain Mail 30, Lamellar Armor 40, Bronze Plate 50, Rimefur Coat 75
	(frost +40, fire -25: "keep his back to the fire and his front to the cold"), Ironclad Plate 95 (dexterity -20; "needs a rope
	to get up from the ground"), Iron Plate 100.
- **Hambry and Gilead.** Ogre-hide Cuirass 105 (life +30; stinks a month), Vigil Cuirass 115 (casts Iron Vigil,
	three charges), Magic Armor 125 (magic +50), Dark Armor 150 (experience -10 percent, "few armourers will put their
	mark on it"), Bright Armor 175 (experience +10), Sunsteel Mail 190 (the smiths sell perhaps one a year, to men
	who have already been hit by something that mattered).
- **Endworld.** Destiny Raiment 200.

## Shields

Reed Shield 2 (Midworld; first drill), Buckler 4, Parry Buckler 6 (Roma duellists; dexterity +6), Small Shield 10,
Spiked Targe 14 (attack +6; "come away with their hands full of holes"), Cinder Shield 28
(Narcissa's potters; fire +40, frost -25), Large Shield 30 (footmen's), Ward Shield 35 (casts Barrier, three charges),
Lifeward Shield 45 (life +30; surgeons' sign), Silver Shield 60 (Gilead; Roma's priests bless them for a fee),
Tower Shield 90 (dexterity -15; Gilead's guards hold a gate with a line of them), Dragonhide Shield 95 (Endworld),
Destiny Aegis 100.

## Rings and charms (accessories that are sold)

The wards and guards against the elements (`magic/elements.md`, `magic/afflictions.md`):

- **Fire**: Ember Ring 300 (Roma's glassmen), Flame Charm 1600 (Kalle's cutters).
- **Frost**: Rime Ring 350 (a Bris smith), Frost Charm 1600 (Narcissa's glass-cutter).
- **Lightning**: Spark Ring 450 (a Bris tinsmith), Storm Charm 2000 (crystal from where storms are born).
- **Holy and shadow**: Halo Charm 2400 (the temples of Hambry and Gilead), Shade Charm 2400 (Narcissa's glassmaker,
	who works only after dark).
- **Poison**: Serpent Ring 450 (Roma's jewellers), Viper Charm 1800 (Kalle's charmers).
- **Sleep**: Wakeful Ring 600 (Roma's clockmakers; "the pinch is the point"), Sentinel Charm 2500 (Hambry's
	watch guild).
- **The rest**: Copper Ring 40 (dexterity), Traveller's Ring 120 (travel points), Lucky Charm 400 (gold), Ward Charm
	1500 (casts Fend, four charges; the mages' guilds sell it in pairs to discourage theft).

## What it costs to wear

Several rungs trade something for it: the dark steel costs experience; Glass Blade life; Warhammer, Ironclad Plate and
Tower Shield dexterity (which also lowers defense); the Cinder Shield and the Rimefur Coat their opposite
element. "Few ask why the blade is so cheap for its weight."
