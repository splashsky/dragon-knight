---
id: monsters/people
summary: The people who fight you: bandits and cheats, deserters, the old garrison's knights, casters, and the pleaders of Hambry's hall.
related: [peoples/roads-and-outlaws, peoples/trades, monsters/undead, monsters/giants, magic/mages, magic/warriors, magic/paladins, things/battlefield-objects, things/consumables, towns/hambry, legends/sayings]
sources: [app/content/monsters/bandit.lua, app/content/monsters/bandit_captain.lua, app/content/monsters/rogue.lua, app/content/monsters/knave.lua, app/content/monsters/scoundrel.lua, app/content/monsters/goblin.lua, app/content/monsters/goblin_shaman.lua, app/content/monsters/insurgent.lua, app/content/monsters/renegade.lua, app/content/monsters/traitor.lua, app/content/monsters/knight.lua, app/content/monsters/armor_knight.lua, app/content/monsters/strong_knight.lua, app/content/monsters/pale_knight.lua, app/content/monsters/dark_knight.lua, app/content/monsters/magician.lua, app/content/monsters/sorceror.lua, app/content/monsters/warlock.lua, app/content/monsters/wizard.lua, app/content/monsters/necromancer.lua, app/content/monsters/bog_witch.lua, app/content/monsters/nihilist.lua, app/content/monsters/advocate.lua, app/content/monsters/fanatic.lua, app/content/monsters/zealot.lua, app/content/monsters/obsessive.lua, app/content/monsters/demagogue.lua, app/content/items/war_standard.lua, continuity.md#where-monsters-live]
---

# People

Monsters that were people, or still are. Their habits are in `peoples/roads-and-outlaws.md`;
this is how they fight. Casters and knights fight with the spells of their class (a Mage's
monster casts the Mage's spells it would know at its level; see `magic/mages.md`,
`magic/warriors.md`, `magic/paladins.md`), plus a few of their own.

## The road: thieves and goblins

Most of them keep to the same trick: **a keg of blasting powder**. On its second turn the
fighter rolls a keg onto the field (never in damp air) and from the third throws a Fire Flask at
it, unless you could not take the blast. Water douses it. (`things/battlefield-objects.md`,
`things/consumables.md`.) The weaker ones throw an Acid Vial or Sleep Powder first.

- **Goblin Shaman** (`goblin_shaman`, 5). A goblin who picked up a few spells from a dropped
	spellbook and has been bragging ever since: weak Hurts, a Heal, two Potions in its belt, a
	dagger. Goblins say the shaman is the one to kill first. Not met on the roads: it only appears
	where content puts it.
- **Rogue** (`rogue`, 8). A thief on the Hambry road, quick with a knife and quicker with a locked
	door; strikes from the shadows and leaves with the coin. The Hambry guard posts a reward for
	each, "usually the price of a good meal". Throws a Fire Flask, rolls a keg.
- **Knave** (`knave`, 9). A petty crook in the back alleys and on the roads between towns: picks
	the purse, then the pocket, and only then asks whether you wanted to fight. The guard knows his
	face, seldom his name, since he changes it every few weeks. Throws Sleep Powder.
- **Goblin** (`goblin`, 10). Small, green and loud, in the hills along the road out of Roma.
	Steals anything it can carry, raids caravans and runs before the guards arrive. Bargains, lies,
	and bargains again. Rolls and lights a keg (in a camp the fire does it).
- **Scoundrel** (`scoundrel`, 12). A bandit who has given up pretending. Cons the roads out of Kalle,
	sells false maps to new arrivals, cheats his own partners. Seldom brave, rarely alone. Throws
	Weakening Dust, eats a herb under a third.
- **Bandit Captain** (`bandit_captain`, 12). Leads a band, in a chain mail coat taken from a knight
	he robbed; loud voice, sharp sword, one herb in a pouch. Works himself into a frenzy once, raises
	Fend under 60 percent life, knits himself under half. Roadside notices offer gold for his head;
	most of them are old. Not met on the roads.
- **Bandit** (`bandit`, 16). A roadside robber in a patched cloak with a club or short sword, waiting
	among the rocks. Works in bands of five or six and seldom fights once he has his pick of the
	wagon: the reason caravans travel with guards. Acid Vial, herb, keg.

## Deserters and rebels

Grown from soldiers the crown stopped paying: they hold the road for tolls. They throw flasks,
drink potions, and roll the keg.

- **Renegade** (`renegade`, 42). The sergeant of the Endworld garrison, until the pay stopped for four
	months running. He took his squad over the wall and now collects tolls on the road he guarded.
	Not cruel for its own sake; has done things he will not describe. Fights as a Warrior (last
	stand under a quarter, second wind under half).
- **Traitor** (`traitor`, 45). Once a captain of the Hambry garrison who sold the gate keys to raiders
	for a share. Serves whoever pays and is loyal to no one who has not paid yet. "I was told you
	would come": weakening dust, acid, potions. He will sell the next gate too.
- **Insurgent** (`insurgent`, 46). Leads farmers and smiths who hold the hill roads above Kalle and
	will not pay the crown's road tax. Not wicked, only tired of watching neighbours hanged for debt.
	Crude spears, short bows, every hidden path. Marks you once the ambush is sprung.

## The old garrison's knights

The crown's own guards, or what is left of them. They raise **the knights' standard** on their
first turn (a War Standard, `things/consumables.md`): everyone on their side deals a quarter more
damage while it stands, and one good blow brings it down. "A knight who has lost his banner
fights like a man who has lost his temper." Plate, shields, war cries; they never answer a hail.

- **Knight** (`knight`, 30). A dead man in full plate, still riding the road he was sent to guard.
	His name was struck from the rolls of Hambry long ago and the armor kept fighting; nobody has
	taken it off him. Seen at dusk on the road between Gilead and Endworld, challenging all passers.
	(Wards off sleep and poison like the dead: `monsters/undead.md`.)
- **Armor Knight** (`armor_knight`, 33). A suit of plate that walks the old barracks road east of
	Kalle. Nobody has seen what is inside; the few who lifted a visor did not live to describe it.
	Its axe splits a shield in one blow.
- **Strong Knight** (`strong_knight`, 35). A knight of Gilead's old garrison told once too often that
	he was not strong enough to hold the gate. He still holds it and takes every challenge
	personally; he rages when hurt. Gilead's market sells his kind a shield, not a sword, since he
	breaks swords.
- **Pale Knight** (`pale_knight`, 39). The last of the garrison knights, bleached white by long years
	in the snow-fields above Kalle; no crest, no banner, and most soldiers in the town think he is
	dead. His lance is not: it is couched on turns 1, 5, 9 (a drawing-back tell, then it lands),
	and he mends himself under two fifths of his life. A Paladin by class.
- **Dark Knight** (`dark_knight`, 43). Once the crown's own guard, until they swore a different oath
	to someone who never gave them a name. Patrol the high passes past Gilead and will hold a road a
	month if nobody stops them. Plain black steel, crest scratched off. They name the oath they
	serve, never the king's. A charged blow every 4th turn; under half "my oath holds" (Stand Fast);
	under a quarter, Last Stand. Upper echelon (`legends/upper-echelon.md`).

## Casters

Learned in towers, guild halls and libraries, thrown out of them, or never admitted.

- **Magician** (`magician`, 8). A robed caster who learned his tricks in a tower near Gilead and was
	thrown out for practising on the students. Quick, with a fire more dangerous than his sword.
	The Gilead guards would like a word, but have not yet found the nerve.
- **Bog Witch** (`bog_witch`, 9). A hag with a hut on stilts in the bogs and a pot of something
	green. Puts travellers to sleep with a wave of the hand, then poisons them to be thorough, and
	throws Pain. Never runs out of magic; drinks from the pot (a herb) under half. Pops a gas
	pocket with her broom. Locals leave a loaf on the path and walk around her patch. Not met on
	the roads; she keeps her patch.
- **Sorceror** (`sorceror`, 11). Learned enough to be dangerous and not enough to be careful. Takes
	apprentices, quarrels with them, forgets why. Common in the towns past Bris, where libraries are
	cheap and nobody checks the guild lists. Their spells carry farther than their manners.
- **Warlock** (`warlock`, 15). Traded a piece of his soul for a stronger spellbook and must keep
	trading. Sells charms and curses from the back rooms of the towns. Polite until he is not.
	Wards himself first.
- **Wizard** (`wizard`, 20). Usually a mage who lost a bet, a debt or a lover and took to the wild.
	Camps in ruined towers past Narcissa, paying for his keep with minor curses on passing traders.
	Strips a warrior's armor (Enfeeble) before the sword is drawn. Midworld's mages say they are no
	true mages, which the wizards take poorly.
- **Necromancer** (`necromancer`, 26). Mages who found the dead more willing to talk than the living.
	In the old graveyards past Gilead, raising what they can and selling the rest to people who
	should know better. Foul air (Miasma), poison, then a Dream and a drain on the sleeper. Most are
	found by smell before they are seen.
- **Nihilist** (`nihilist`, 47). A learned man from Gilead who decided nothing matters and set out
	to prove it by burning archives and poisoning wells. Cold, articulate, with a following of bored
	students. One affliction at a time: a plague, or from the third turn a blaze. "He simply cannot
	see why anyone should be spared."

## The pleaders of Hambry's hall

In Hambry the hall of the pleaders sits in judgement on anyone who comes in without a receipt; bring a
witness and a bag of coin (`towns/hambry.md`). Four hold it: the Advocate and the three of his following.
They ward off weakening in part, and the followers have given up sleep and manners.

- **Advocate** (`advocate`, 35). The first of the four pleaders. Will argue your case, into the
	ground (he saps your strength). Hard to talk down.
- **Fanatic** (`fanatic`, 36). The loudest of the followers, shouting down anyone who doubts the
	Advocate. Has given up sleep, food and most manners. The chant is followed by a rush: its second
	turn is a rage.
- **Zealot** (`zealot`, 38). The Fanatic's more patient brother: a quiet voice persuades better than
	a shout. Walks the road between Hambry and Gilead with a lantern and a list of names, remembering
	everyone who argued with the Advocate. A sleep song every 4th turn ("Breathe. It is almost
	over."), a smiting prayer, mends under two fifths.
- **Obsessive** (`obsessive`, 40). The last and most narrow-minded; fixed on one word. Crowds the back
	rooms of the hall saying it until a visitor says it too (Maim, over and over, until the magic
	runs dry). The Advocate finds them useful.
- **Demagogue** (`demagogue`, 48). Gathers crowds in the squares of Gilead and tells them the crown is
	starving them on purpose, often partly right, which makes him dangerous. Followers pay in coin
	and labor; his guards are paid in the bread taken from the granary. Rouses the crowd in his
	first turns (Rage), turns it on you when hurt (Curse), two potions.
