---
id: peoples/roads-and-outlaws
summary: Travellers, caravans and inns on the roads, and the people who prey on them: bandits, thieves, tollmen, deserters and the unpaid garrisons.
related: [world/overview, towns/midworld, towns/roma, towns/bris, towns/kalle, towns/narcissa, towns/hambry, towns/gilead, towns/endworld, peoples/trades, lands/dry-country, lands/diggings, lands/greymoor, lands/storm-barrens, lands/ashlands, monsters/people, monsters/others, monsters/giants, monsters/fey-and-spirits, things/battlefield-objects, legends/sayings]
sources: [app/sql/seed.sql, app/content/monsters/bandit.lua, app/content/monsters/bandit_captain.lua, app/content/monsters/knave.lua, app/content/monsters/rogue.lua, app/content/monsters/scoundrel.lua, app/content/monsters/insurgent.lua, app/content/monsters/renegade.lua, app/content/monsters/traitor.lua, app/content/monsters/dark_knight.lua, app/content/monsters/pale_knight.lua, app/content/monsters/orc.lua, app/content/monsters/ogre.lua, app/content/monsters/troll.lua, app/content/monsters/goblin.lua, app/content/monsters/imp.lua, app/content/monsters/polgergeist.lua, app/content/monsters/zealot.lua, app/content/items/traveller_ring.lua, app/content/items/scouts_jerkin.lua, app/content/items/travel_tea.lua, app/content/items/hi_potion.lua, app/content/items/fortune_drop.lua, app/content/spells/reaver.lua, app/content/classes/warrior.lua, app/content/fields/fog.lua, app/town/inn.lua, continuity.md#Decided]
---

# Roads, travellers and outlaws

The towns are far apart and the roads between them are where trouble is. This chunk is who walks the
roads, where they sleep, and who waits for them. (The towns' order, distances and danger by distance are
in world/overview.md.)

## The roads in the lore

- Midworld to Roma: "the long road... where the slimes are many and the inns are few", where Warriors
	learn their trade; trolls sleep under its bridges and toll the traders.
- Roma to Bris: goblins on the hills, a hellcat on a ledge, a drakelor in the rocks, a Blaze working along it.
- Midworld to Kalle: graveyards and ruined inns where ghosts moan about a debt nobody remembers.
- Bris to Kalle: the hot road, dry and lined with cliffs; see lands/dry-country.md.
- Roma to Kalle: carters wear Traveller's Rings on it, so that the stone catches the light and someone at the
	next inn knows they have come far.
- Kalle to Narcissa: wooded slopes and the "forest road past Kalle".
- The road to Narcissa: the inns are a day apart, so travellers carry the Life spell more than any potion.
- Narcissa to Hambry: lycans on nights of the full moon; moonlit inns with a succubus.
- Hambry to Gilead: a zealot with a lantern and a list of names.
- Gilead to Endworld: a dead knight in plate at dusk who challenges anyone who passes. The road to Endworld has fear on it
	("a steady hand and a good night's sleep keep it at bay") and the Black Daemon, whose name mothers use to frighten children.
- "The northern road" is where the reavers were; see below.

## Who travels

- Carters and caravan folk: drivers who shake out their boots each morning and paint their wagons with pitch
	against wyverns; nomads with a knotted band for each hand that walked with them; guards on contract (a dozen
	Hi-Potions at a time, signed for), who say the Brute is not stupid, "only uninterested in anything that cannot
	be picked up and thrown".
- Scouts who run between the towns and buy Scout's Jerkins in pairs, one to wear and one to dry; boys who want
	to be runners keep sparrow feathers.
- Pilgrims going north, buying blessed maces at Hambry and Halo Charms at the temples; mercenaries bound for
	the cold country with Cinder Blades "by the pair"; trappers with three bottles of Frost Ward for the winter crossing.
- Hunters, herders, minstrels (who play at Hambry's inns for their supper), gamblers (who wear Wakeful Rings
	through a whole game), road-wardens, and the adventurers whose first fight is a Blue Slime.
- Travel Tea at the market stalls "chases the road tiredness"; Trail Snacks keep the legs under you.

## Inns

A night at an inn refills HP, MP and TP and recharges what you wear. The price rises with the road, from 5 gold in
Midworld to 125 in Endworld (the table is in world/overview.md).

- Innkeepers say the Sleep spell works as well on drunk customers (Midworld); pay Mages for Dream when a guest will not
	settle (Bris); buy Wakeful Rings for the night watch (Bris); say a Paladin who knows Mend needs fewer rooms (Roma).
	A Bris innkeeper once said Travel Tea was the only thing he had sold that people came back for; at the crossroads on
	the Narcissa road, innkeepers sell cheap ale to the carters who wait for the fog to lift.
- What goes wrong: imps hide the keys to inn doors and whisper bad prices to shopkeepers; polgergeists throw the
	furniture, so innkeepers on the road out of Kalle pay a priest to walk the rooms with salt before a bed goes out; an
	incubus sits at inns along the road to Narcissa as "a handsome stranger"; a succubus in the moonlit inns between
	Narcissa and Hambry; a nightmare visits sleepers beyond Narcissa; ruined inns have ghosts and a haunt.
- Mages keep a charm of salt by the bed; priests in Hambry say a blessed cloth over the eyes breaks an incubus's illusion.

## Outlaws of the road

- **Bandits** (Bandit 16, Bandit Captain 12): "work in bands of five or six and seldom fight once they have had their pick of the
	wagon. The reason caravans now travel with guards is mostly them." The captain wears a chain mail coat taken from a
	knight and carries one herb for when he is hurt; roadside notices offer gold for his head, "and most of them are old".
	They say "Stand and deliver" and, when losing, run for the rocks. They roll blasting powder at pursuers (see
	things/battlefield-objects.md). The bandits of Narcissa call a morning fog the best time of the year for business.
- **Thieves**: Knave (9), who works "the back alleys of the towns and the roads between them" and changes his name every few weeks;
	Rogue (8), who works the Hambry road, and whose reward in Hambry's guard post is "usually the price of a good meal";
	Scoundrel (12), who runs cons on the roads out of Kalle and sells false maps; cutpurses near Midworld (their holed
	coins are Fortune Drops); goblins, who raid caravans and run before the guards arrive.
- **Tollmen**: trolls under the bridges, orcs of the hills past Narcissa ("a toll, then another on the way back"), an ogre
	east of Gilead ("pay the toll or go the long way round").
- **Reavers**: "the reavers of the northern road were never gentle men"; their trick of putting blood on the blade back into the
	body that spilt it passed to the paladins who ride with the caravans (the Reaver spell).

## The crown, the garrisons and the deserters

The garrisons of the old crown stand at the towns' gates and on the roads. When the crown does not pay them, they
turn. The lore keeps a run of cases:

- **Renegade** (42): a sergeant of the Endworld garrison until the pay stopped for four months; he took his squad over the wall and
	collects tolls on the road he once guarded.
- **Traitor** (45): a captain of the Hambry garrison who sold the gate keys to the raiders for a share; he serves whoever pays.
- **Insurgent** (46): farmers and smiths who hold the hill roads above Kalle and will not pay the crown's road tax; "not wicked, only
	tired of watching his neighbours hanged for debt".
- **Dark Knights** (43): once the crown's own guard, now sworn to another; they hold the high passes past Gilead.
- **Pale Knight** (39), the last garrison knight bleached white in the snow above Kalle; **Strong Knight** (35), who holds
	Gilead's gate; **Knight** (30), a dead man in plate on the Gilead road, struck from the rolls of Hambry; **Phantom** (14), a soldier who
	died without his pay and still stands guard.
- Sellers in Gilead's market sell a Strong Knight a shield and not a sword, "since he breaks the swords".
- The Demagogue of Gilead says the crown is starving the people on purpose, "and is often partly right".

See monsters/people.md for how these fight.

## Habits of the road

- Carters wait for fog to lift; a traveller who lies down by the road after dark may not wake when he means to (sleep
	comes deeper in the dark).
- Travellers on the Gilead road stand clear of old dead trees while a gale blows.
- The road-wardens say the Black Dragon leaves a traveller alone if he leaves it something shiny, "though nobody has tested
	that lately".
