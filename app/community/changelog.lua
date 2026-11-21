-- community/changelog.lua :: GET /changelog, the game's version history. Everything up to
-- 1.1.11 is the original changelog.txt from dragon.se7enet.com (via the Internet Archive),
-- kept verbatim; newer releases go on top in the same style.
local game = require("lib.game")
local view = require("lib.view")

local changelog = {}

changelog.RELEASES = {
	{
		version = "3.1.0", date = "unreleased",
		changes = {
			"The page is at most 1200 pixels wide, so it stays together on wide screens.",
			"The Babble Box is a small chat window you open and close from the Functions box, instead of a panel in the right column and the town page. Drag it by its top edge wherever you like and resize it by its corner: it stays open, where you put it, from page to page until you close it, and stays usable over the shop's dialog. Its messages fill it, each with the name above the message, and you type in a bar across its foot with the send button inside. The chat also has a page of its own, /babble.",
			"The Towns box lists each town on your map with what the trip costs in TP. The town you are in, the towns your TP don't cover (hover for how many more you need) and, during a fight, all of them are greyed out. Without maps it tells you where to buy them.",
			"The fight menu is a hotbar: press 1 to attack and 0 to run away, and 2 to 9 for your spells, your potions and the gear that casts spells (or click them, as before). Each button shows its key. When you can't act, any number key presses Continue.",
			"Arrange your hotbar on the new Hotbar page (in the Functions box) when you aren't fighting: pick an action for each key, or drag them around. Nothing moves unless you move it: a spell or item you get later takes the first free key when your next fight begins, what doesn't fit waits under More in the fight menu, and a potion you've used up or gear you've taken off keeps its key, greyed out, until you have it again (schema version 17, run dk migrate).",
		},
	},
	{
		version = "3.0.0", date = "11.21.2026",
		changes = {
			"Loading a page no longer changes the game: reloading the fight page shows the last round again instead of counting a turn, and the victory page can be reloaded or revisited without losing it (schema version 15, run dk migrate).",
			"An encounter now begins the moment you step into it, the monster's first strike included, and the rewards are paid by the blow that wins the fight.",
			"After a death the fight page still shows how the fight ended, until you set out again.",
			"The game no longer loads whole pages as you play: links and buttons bring only the parts of the page that changed, so the page stays put, the chat keeps what you were typing, and the live chat stays connected; Back and Forward work as before. Without JavaScript everything works as it always did.",
			"A thin bar at the top of the page shows when the server takes more than a moment to answer.",
			"Pages you have open in other tabs or on another device keep up: what you do in one shows in the others within a moment, without reloading them.",
			"A command that can't be carried out in a fight (not enough MP, a spell you haven't learned, an empty wand) is now explained right on the fight page, above your commands, instead of on a page of its own.",
			"Reloading the fight page after a round no longer offers to send the command again: every command now comes back to the fight page, which shows what happened.",
			"Taking a dropped item into a full bag without choosing what to discard now says so on the drop page.",
			"Shops show their wares as pictures, grouped into weapons, armor, shields and items. Point at one (or focus it) for a tooltip made for shopping: the price and your gold (or how much more you need), its stats with how they compare to what you wear (a gray +0 where nothing changes), what it does, and what your old piece sells back for. What your gold can't cover yet is greyed out. Selling works the same way, its tooltip saying what the shop pays.",
			"Midworld's wares have pictures: the Stick, Branch, Club, Skivvies, Clothes, Leather Armor, Reed Shield and Buckler, in the shop, your bag, the Inventory panel and their tooltips.",
			"The compass is the original picture again: click its north, west, east or south arm to walk, or use the arrow keys.",
			"Buying happens in a dialog over the shop, laid out to help you decide: the item with its price tag, what it changes next to what you wear now, and your choices as large buttons that each say how much gold you'll have left. Weapons, armor and shields no longer have to be worn at once: buy them to your bag, to wear (your old piece goes into the bag), or to wear with your old piece sold. Once you buy, the shop behind the dialog is up to date; Escape or \"Not now\" closes it. Without JavaScript the purchase is a page of its own.",
			"A lighter Default theme: headings are text (in small capitals, the page's title larger) instead of boxed pictures, the columns are set apart by space instead of lines, the chat is in light stripes, and the footer is a plain row of small print with the theme picker in it. The Location panel is shorter: where you are as its heading (\"In Midworld\", \"Exploring\", \"Fighting\"), then your coordinates (\"3N, 5W\") and the map on one line. The Retro theme keeps the original pictures for its headings and links.",
			"Item and skill icons sit on a softly grained, parchment-like tile in a gold frame (steel for Attack and Run, crimson for quest items), in the fight menu, the shops, your bag and the tooltips.",
			"Monsters can speak: a few now greet you, taunt you when they are winning, complain when they are losing or hurt, and have a last word when they fall (on the victory screen) or when you do (on the death screen). Nothing they say is certain: every moment speaks only by chance, some lines come once a fight at most, and some only in a given situation (asleep and poisoned at once, nearly beaten, facing a sleeping hero). Meet the Troll, the Necromancer or the Red Dragon to hear them.",
			"Pages change smoothly: whatever you do that changes the page (visiting the inn and resting there, the shops, buying and selling, the inventory, ...) fades the old one out and the new one in.",
			"Changes of state are smoother: when a fight begins, when you win, die or get away, and when you arrive in a town or set out from one, the page fades out through a short caption saying what happened and the new one fades in. Arriving in a town and setting out linger a little longer. Click or press a key to skip it. The victory screen is drawn the same way, \"Victory!\" with what the fight paid, and the fight fades straight into it.",
			"Walking or travelling into a town now takes you straight to the town; the \"You may now enter this town\" page is gone.",
			"Items that cast a spell can be single use: the inn doesn't recharge them, and the last charge uses them up. Charges now read \"3/5 Charges\" (schema version 16, run dk migrate).",
		},
	},
	{
		version = "2.4.0", date = "11.20.2026",
		changes = {
			"Added tooltips: pointing at a spell's button in the fight menu or the Fast Spells box (or focusing it with the keyboard, or pressing and holding it on a touch screen) shows its name, MP cost, where it can be cast, what it does and its lore, also when you don't have the MP for it.",
			"The gear in the Inventory panel, the monster you are fighting and the classes on the registration page have tooltips too; tooltips stay inside the window, flipping to the other side near an edge.",
			"Classes, spells, items, monsters, statuses and summons can have lore, a little story shown in their tooltips and on the help pages; the Mage, Warrior and Paladin, Heal, the Herb and the Blue Slime have some to begin with (schema version 13, run dk migrate).",
			"Administrators can write or change an entry's lore on its admin page.",
			"Attack and Run are now icon buttons in the fight menu, with tooltips: Attack shows your attack power and weapon; Run sits apart from Attack so it isn't pressed by accident.",
			"Items show their tooltip on the Inventory page, in the shops (the items for sale, the purchase page and the Sell list) and when discarding.",
			"Added Magic Bolt, a 1 MP spell for 3 to 4 damage: every Mage knows it from the start, and Mages now start with 5 MP (their gains per level are the same). Existing Mages get the 5 MP and learn Magic Bolt when the server is migrated (schema version 14, run dk migrate).",
			"Classes can give new characters spells from the start (start_spells in the class file).",
			"Added the Wand, the first item with an effect: a weapon sold in Midworld for 75 gold that casts Magic Bolt in a fight without costing MP, five charges at a time. Its button sits in the new Gear group of the fight menu, with its charges on a badge.",
			"Items can cast a spell with charges (casts and charges in the item file); each item keeps its own charges, full when bought or found, and resting at an inn recharges the items you wear.",
			"Items in the fight menu are icon buttons too, with how many you have on a badge; ones you can't use right now (a Herb at full HP) are greyed out.",
			"Items have pictures: the Herb, Potion, Ether and Wand show theirs in the bag, the Inventory panel, the shops, the fight menu and their tooltips (icon in the item file; dk check fails if the file is missing).",
			"Shops no longer say \"Already purchased\": you can buy any item the town sells as often as your gold and your bag allow, even a copy of the weapon you are wearing.",
			"The fight menu puts your gear's abilities next to Attack, hides Spells and Items when you have none, and the compass is hidden while you fight.",
		},
	},
	{
		version = "2.3.1", date = "11.20.2026",
		changes = {
			"Fixed the monster's HP bar not starting full: the HP a monster is rolled with is now its full health for the fight.",
			"Redesigned the Character panel to be more compact: name and level on one line, and HP, MP and TP as slim bars with their values.",
			"HP, MP and TP bars are drawn with CSS gradients instead of images, and the monster and ally bars in fights are the same bars as the Character panel's.",
			"Condensed the Inventory panel: your bag comes first, then your gear and accessory slots in one tight list.",
			"Spells are now icon buttons in the fight menu and the Fast Spells box, with their MP cost on a badge and their name and cost as a tooltip; spells you don't have the MP for are greyed out. Heal has its own icon, the others a default one for now.",
			"Spell content files can name an icon (public/images/skills/<icon>.png); dk check fails if the file is missing, and administrators can change a spell's icon on its admin page (schema version 12, run dk migrate).",
		},
	},
	{
		version = "2.3.0", date = "11.20.2026",
		changes = {
			"Made the server several times faster: each request's Lua VM is restored from a snapshot instead of being built anew, workers write responses themselves, and requests take turns on the database without sleeping.",
			"Moved the server to epoll with a timer heap; an idle connection no longer holds a buffer, and static files are served from memory (or with sendfile) with ETags and 304s; fonts (ttf, otf, woff) got their proper types.",
			"The number of workers follows the CPU count by default (workers = 0); a request that waited too long for a worker gets a quick 503 with Retry-After (queue_timeout_ms).",
			"Moved log writing to a background thread; added access_log = false to turn off the per-request lines.",
			"Moved database checkpoints to a background thread, and fixed the database log file growing without bound under steady load.",
			"Added dk stats and an admin Server page with the server's live metrics, and make bench, a load generator with scripted players.",
			"Added themes: Default (new artwork: a snowy background and a new logo) and Retro (the original look); choose one in the page footer, logged in or not.",
			"The whole site now uses the Vollkorn typeface, a little larger than the old 11px Verdana; the side columns are slightly wider to fit.",
			"The server can now push live updates to open pages (server-sent events on /live): events are sent only once the change behind them is saved, a page that reconnects gets what it missed, and players who stop reading are cut off.",
			"Added settings for live updates (max_streams, max_streams_per_ip, stream_queue_bytes, stream_heartbeat_ms, stream_replay_events, stream_replay_seconds), their metrics on the admin Server page and in dk stats, and make bench BENCH_SCENARIO=realtime.",
			"The Babble Box is now a live chat in the right column of every game page (larger in towns and on its own page, /babble): messages appear without reloading, the last 50 are shown, one message every 2 seconds at most, and administrators can delete messages.",
			"Who's Online and the count of players online update live; a player with a game page open counts as online.",
			"Open pages show notices for new news posts and for replies in forum threads you started or posted in.",
			"Added a broadcast banner (admin Broadcast page): a short announcement at the top of every page, shown live, with an optional expiry; players can dismiss it.",
			"Logging out or changing the password ends the live updates of the pages left open.",
			"A browser keeps one live connection, shared by its tabs; without JavaScript everything works as before, with page loads.",
			"Chat messages keep their author's account (schema version 10, run dk migrate); added online_seconds and presence_sweep_seconds to the config.",
			"Game pages read Who's Online from an index of the players online instead of going through every account (schema version 11, run dk migrate).",
			"The town's Who's Online box lists the first 50 players and links to the new /online page for everyone else.",
			"Fights play out in place: each round's lines appear one by one while the HP and MP bars, statuses and allies change, then the page updates without reloading; the victory, item drop and death pages follow the same way. A click or any key skips ahead, and there are no delays for players who prefer reduced motion.",
			"Every fight command carries its round, so a double click or an old tab no longer plays an extra round: it shows the fight as it is now.",
			"The fight round counter no longer stops at 255 (the original's limit), so the protection against double clicks also holds in very long fights.",
			"Added make bench BENCH_SCENARIO=realtime-mixed (1,000 players with live connections, 50 of them playing, chatting and reconnecting) and BENCH_SCENARIO=soak (the same for an hour, checking memory, file descriptors and errors); both also run against the sanitizer builds (BENCH_BUILD=dbg or tsan).",
		},
	},
	{
		version = "2.2.0", date = "11.19.2026",
		changes = {
			"New fight engine: a fight is a round of turns (yours, your allies', each monster's) with effects that last several turns.",
			"Added statuses, a new kind of content file: timed effects on anyone in a fight, like poison or regeneration, shown on the fight page with the turns they have left; casting one again replaces it.",
			"Monster sleep and the damage and defense buffs are statuses now; fights without new effects play exactly as before, and the player can now be put to sleep and monsters buffed.",
			"Added spells that act over two turns: Hyper Beam hits hard, then you must recharge; Solar Beam gathers sunlight for a turn, then fires. While you can't act the fight page offers only Continue.",
			"Added summons, a new kind of content file: allies that fight alongside you for a few rounds; monsters may attack them instead of you. The Allies setting caps them (default 1).",
			"Added the Poison, Regen, Hyper Beam, Solar Beam and Call Wolf spells (no class learns them by default) and the Antidote and Regen Potion items.",
			"Some statuses also work outside fights and tick with every move on the map, like the Regen Potion's; the character page lists them.",
			"Monsters choose their actions and targets by weight, ready for monsters with spells and items.",
			"Fights are encounters of one or more waves of monsters (one monster for now), with rewards per monster.",
			"A fight in progress is kept in its own tables; dk migrate moves fights in progress there, and they go on.",
			"Errors in a status's or summon's code are logged and remove it; the fight goes on.",
			"Admin pages for statuses and summons; the user editor shows the fight in progress and the statuses.",
			"The help page on spells lists the statuses and allies.",
			"Monsters are now content files too; admins can override their stats per server on a new Monsters page (it replaces the monsters editor), and dk migrate keeps edited stats as overrides.",
			"Monsters have magic points (the Mage's at their level) and can carry equipment, use items and cast spells, each chosen by weight and an optional condition; items run out per encounter.",
			"Added three monsters that show it off, not met at random: the Goblin Shaman, the Bog Witch and the Bandit Captain.",
			"The help page on monsters shows their magic points and the spells, items and equipment of those that have them; the fight page shows the MP of a monster that casts spells.",
			"Fights against the original monsters play exactly as before.",
		},
	},
	{
		version = "2.1.0", date = "11.19.2026",
		changes = {
			"Removed difficulty levels; everyone plays at the original Easy difficulty.",
			"Experience needed per level, TP gains and HP milestones now follow formulas fitted to the original level table.",
			"Classes are now content files that can be edited and added without code changes; admins can override names, descriptions and starting stats per server.",
			"Replaced the levels editor and the class name settings with a Classes page in the admin panel.",
			"Added dk content sync and dk content status; dk check also validates the content files.",
			"Spells are now content files too, each with a description and a list of effects; new spells can be added and taught through a class file without code changes.",
			"Replaced the spells editor with a Spells page in the admin panel: names, descriptions, MP costs and effect amounts can be overridden per server.",
			"The spells a character knows are kept in their own table; the user editor takes spell names by key.",
			"Warrior and Paladin now use the same experience curve as the Mage (scaled by their own first step); classes can still define their own.",
			"Items and monster drops are now content files too; drops are accessories, and admins can override names, prices, power, modifiers and drop levels per server on a new Items page (it replaces the items and drops editors).",
			"Added an inventory: a bag of 12 slots (stacks count once, quest items don't count; size in the main settings) next to the equipped weapon, armor, shield and three accessory slots, with an Inventory page to equip, take off, use and discard items.",
			"Added Herbs, Potions and Ethers, sold in towns; use them from the inventory or in a fight (it takes your turn).",
			"When buying a weapon, armor or shield you can keep the old one in your bag or sell it, and shops buy back items from your bag.",
			"Monster drops go into the bag (or are left behind); with a full bag you can throw something away first.",
			"Character stats are computed from base stats and the equipped items, so equipping and removing items is always exact.",
			"The town editor lists the items a shop sells by key; the user editor shows the character's inventory and effective stats.",
			"Spells and consumables are now scripted: their content files hold what they do as Lua code, and their power, MP cost and messages as data that admins can override per server; the original ones work exactly as before.",
			"Spells and items are written for a caster and a target, with optional wording for monsters, ready for monsters that cast spells and use items.",
			"Errors in a spell's or item's code are logged and cost nothing: no MP, item or turn is spent.",
			"Spells and consumables whose content file was deleted are kept by their owners but can no longer be used.",
			"The help pages show each spell's MP cost and power and each consumable's power.",
		},
	},
	{
		version = "2.0.0", date = "11.19.2026",
		changes = {
			"Complete engine rewrite: a single program with its own HTTP server in C, the game in Lua and the database in SQLite. No PHP, MySQL or web server needed.",
			"Game code and templates take effect on the next page refresh, without a restart.",
			"Every request runs in a fresh Lua VM, taken from a pool of pre-warmed spares.",
			"New template language, compiled to Lua; everything shown is HTML-escaped by default.",
			"Clean URLs (/inn, /shop/buy/3, /forum/thread/7, ...) and HTML5/CSS markup with the original images and layout.",
			"Installer and upgrade scripts replaced by the dk install command.",
			"Added dk backup and make targets for releases, deployment and migrations (make dist, make deploy, make migrate), and make run to play locally in one step.",
			"Passwords are stored as PBKDF2-SHA256 hashes; the alphanumeric/10 character password rules are gone.",
			"Logins use server-side sessions; changing or resetting a password logs out other sessions.",
			"Added CSRF protection to every form.",
			"All database queries are parameterized, and all user text is escaped on output (babblebox, forum, news, names).",
			"Fixed URL cheats that allowed buying items or maps in the wrong town, traveling to towns that don't exist, casting spells you don't know and picking invalid drop slots.",
			"Emails (verification, lost password) are written to an outbox folder instead of being sent. Email verification is off by default.",
			"The forum shows a message when the built-in forum is turned off, and its paging works.",
			"Admin: removed the page compression option, added paging to the user list, added setting a user's password, fixed swapped labels in the user editor.",
			"Fixed the Bris item list so it sells the Buckler and Small Shield.",
			"The sell-back value of the item you replace now counts toward the shop price.",
			"Heal spells can't be cast at full HP, in town or in fights, and never lower your HP.",
			"Monsters can block you from running away again; a blocked run gives the monster a turn, and you can die fleeing.",
			"Damage/defense spells now end with the fight, including after running away or dying.",
			"Fixed problem where goldbonus was added to experience instead of gold (again).",
			"A victory now grants every level its experience covers.",
			"Dying on a spell turn no longer refunds the spell's MP.",
			"Equipping a drop into an empty slot now lowers current HP/MP/TP to the new maximum.",
			"\"This monster has dropped an item\" only shows when there is an item.",
			"Level 99 characters now see the experience needed for level 100.",
			"Spells of an unknown type are refused instead of doing nothing.",
			"Strength/dexterity bonuses on items count toward attack/defense power in any slot.",
			"Victory experience and gold can't go below zero.",
			"The forum is split into boards, with a News board where only admins start threads.",
			"News posts have titles and authors, and each one gets its own discussion thread.",
			"Town news shows the first paragraph of the latest post, with Read more and its reply count.",
			"Added a news archive page.",
			"Added the dk migrate command to upgrade existing databases.",
		},
	},
	{
		version = "1.1.11", date = "3.26.2006",
		thanks = "Thanks to r0xes & Adam. :)",
		changes = {
			"Added recursive htmlspecialchars to the rest of the superglobal security in lib.php.",
			"Fixed a bug that allowed blank passwords.",
			"Updated copyright dates as necessary.",
		},
	},
	{
		version = "1.1.10b", date = "10.25.2005",
		changes = {
			"Fixed addslashes_deep() to actually add slashes, instead of strip them. Man, I'm dumb.",
		},
	},
	{
		version = "1.1.10a", date = "10.1.2005",
		thanks = "Thanks to obliv. :)",
		changes = {
			"Fixed a security error.",
		},
	},
	{
		version = "1.1.10", date = "3.13.2005",
		thanks = "Thanks to Gary13579. :)",
		changes = {
			"Fixed a security error.",
			"Added verified/banned checking in the built-in forum.",
		},
	},
	{
		version = "1.1.9", date = "3.2.2005",
		thanks = "Thanks to xudzh and ChAoS and Adam. :)",
		changes = {
			"Character names now have validation checking.",
			"Fixed babblebox bug when used in Internet Exploder.",
			"Updated the admin menu link to the main game page for the new path.",
			"Updated the link to the official DK forums in the Help file.",
		},
	},
	{
		version = "1.1.8", date = "2.6.2005",
		changes = {
			"Added extra security to prevent SQL injection exploits.",
			"admin.php is now in the game root directory rather than the /admin/ sub.",
		},
	},
	{
		version = "1.1.7", date = "12.29.2004",
		thanks = "Thanks to Adam. :)",
		changes = {
			"Fixed URL cheat that allowed people to continue fighting after victory.",
		},
	},
	{
		version = "1.1.6a", date = "11.20.2004",
		changes = {
			"Fixed problem where goldbonus was added to experience instead of gold.",
			"Fixed a typo in fight.php.",
		},
	},
	{
		version = "1.1.6", date = "11.6.2004",
		thanks = "Thanks to Shadowbq, joshman, Adam, and Tsufo. :)",
		changes = {
			"Fixed variable name reference in fight.php.",
			"Fixed URL cheat that allowed people to buy any item from any town.",
			"Fixed URL cheat that allowed people to travel anywhere without having the map.",
			"Fixed display bug in the error messages generated by cheat attempts.",
			"Fixed admin/editlevels that caused all level values to be reset to zero.",
		},
	},
	{
		version = "1.1.5", date = "9.22.2004",
		thanks = "Thanks to Adam and Shadowbq. :)",
		changes = {
			"Fixed Travel To cheat that allowed you to escape from fights.",
		},
	},
	{
		version = "1.1.4", date = "8.23.2004",
		thanks = "Thanks to Gary13579 and Maebius. :)",
		changes = {
			"Fixed URL cheat that allowed people to get healed for free.",
			"Changes to make babblebox more secure from html/bbcode exploits.",
		},
	},
	{
		version = "1.1.3a", date = "5.23.2004",
		changes = {
			"Updated forum.php for use with new checkcookies() location.",
		},
	},
	{
		version = "1.1.3", date = "5.20.2004",
		changes = {
			"Fixed several bugs related small bugs related to new version info location.",
			"Moved checkcookies() out of login.php, into cookies.php.",
			"Deleted admin/lib.php, moved requisite functions into standard lib.php.",
			"Fixed minor display bug in admin template.",
		},
	},
	{
		version = "1.1.2", date = "4.24.2004",
		changes = {
			"Fixed bug with default spell/town field contents.",
			"Fixed bug with updating new spell on levelup.",
			"Updated help file to point to new forums address.",
			"Version info is now handled through lib.php, instead of config.php.",
		},
	},
	{
		version = "1.1.1", date = "3.1.2004",
		changes = {
			"Fixed map buying bug.",
			"Fixed adminemail bug when sending email (tnx Mantagnana).",
		},
	},
	{
		version = "1.1.0", date = "2.27.2004",
		thanks = "Thanks to Miker, Yop, Mantagnana & Maebius for bug reports & feature ideas. :)",
		changes = {
			"Added option to verify registration emails.",
			"Added options to turn off display of news/online/babblebox in towns.",
			"Added gameurl and adminemail fields to control table.",
			"Added ability to ban a user without deleting the account.",
			"Added rules for passwords (alphanumeric, maxlength=10).",
			"Added page where users can change their passwords.",
			"Added a page for lost passwords.",
			"Fixed bugs in users.php to use doquery() instead of mysql_query().",
			"Fixed bug in installer program when creating the admin user account.",
			"Changed the way towns and spells are handled in the user account.",
			"Removed some deprecated code from the onlinechar() function.",
		},
	},
	{
		version = "1.0.4", date = "2.14.2004",
		thanks = "Thanks to Maebius & Mantagnana. :)",
		changes = {
			"Fixed babblebox bug.",
			"More checks to ensure experience/gold doesn't go over the database field limit.",
			"Fixed bug with dropcode and levelups.",
			"Added visual warning if your exp/gold are maxed out.",
			"Fixed minor experience bug in Extended Character Stats.",
			"Fixed minor display bug in admin template.",
		},
	},
	{
		version = "1.0.3", date = "2.6.2004",
		thanks = "Thanks to Maebius for reporting these. :)",
		changes = {
			"Fixed problem with monster's turn in fight.php",
			"Once again tried to fix the paths bug, this time by eliminating it altogether.",
		},
	},
	{
		version = "1.0.2", date = "2.4.2004",
		thanks = "Thanks to WolfSinger for reporting these. :)",
		changes = {
			"Fixed bug in installer that prevented it from working with MySQL 3.",
			"Fixed more bugs with random number generation.",
			"Hopefully fixed problem with paths on some systems. New variable in lib.php.",
		},
	},
	{
		version = "1.0.1", date = "1.29.2004",
		changes = {
			"Added basic map popup.",
			"Added optional \"call home\" function to installer.",
			"Added checker to ensure install.php has been deleted before running.",
		},
	},
	{
		version = "Final", date = "1.24.2004",
		changes = {
			"Added installer script.",
			"Added news posting to control panel.",
			"General cleanup, etc.",
		},
	},
	{
		version = "RC2", date = "1.20.2004",
		changes = {
			"A few more minor template changes.",
			"Fixed missing spells list in fight screen.",
			"Added ability to see character stats for Who's Online people.",
			"Added \"Next Level\" experience points in Extended Stats popup.",
			"Completely new and finalized Help section.",
		},
	},
	{
		version = "RC1 Aero", date = "1.16.2004",
		changes = {
			"Fixed database to allow floats in difficulty mods.",
			"A couple minor template changes.",
			"Fixed bug that prevented med/hard difficulties from gaining experience.",
			"Fixed several small bugs with random number generation.",
			"Dying is now integrated into the fight screen for better user feedback.",
			"Fixed bug that allowed victory gold/experience exploit.",
			"Added internal forums.",
			"Added some admin options.",
			"Added user auth level (user/admin).",
			"Added Admin Control Panel.",
			"Fixed bug that allowed users to post blank messages in babblebox.",
			"Added option to close game during maintanence.",
			"Added administration control panel.",
		},
	},
	{
		version = "Beta 3 Aqua", date = "12.18.2003",
		changes = {
			"Fixed problem with red status bars not showing up sometimes.",
			"Added control settings table for changing major game options.",
			"Altered several little chunks to accept values from controlrow instead of hard coding.",
			"Other minor changes to pull away from the hard-coded \"Dragon Knight\" name.",
			"Changes to map buying screen to include town coordinates.",
			"Added shoutbox + safety features to main town screen.",
			"Added Who's Online to main town screen.",
			"Added News box to main town screen.",
			"Picking a monster when a fight starts is now more efficient.",
			"Monsters now have a chance to get the first swing.",
			"Monsters now have a chance to block you from running away.",
		},
	},
	{
		version = "Beta 2 Fira", date = "12.14.2003",
		changes = {
			"Fixed bug with special items to keep you from having more than your max HP/MP/TP when you get rid of the item.",
			"Fixed death so you now get back 25% of your HP.",
			"Added monster item drops.",
			"Rebalanced town TP price.",
			"Added TP price to map purchasing screen.",
			"Added output compression to save bandwidth.",
			"Added new HP/MP/TP status bars in rightnav.",
			"Rewrote explore.php to be more efficient & to help with the IE problem.",
			"Fixed buyback of old items to use whole numbers instead of fractions.",
			"Fixed IE problem that prevented/fuxx0r'd movement.",
		},
	},
	{
		version = "Beta 1 Terra", date = "11.22.2003",
		changes = {
			"Complete engine rewrite. Numerous new features.",
		},
	},
	{
		version = "Alpha 1", date = "9.19.2003",
		changes = {
			"Initial public release.",
		},
	},
}

-- GET /changelog (public, like the help pages)
function changelog.page(req)
	local gamename = game.control().gamename
	local releases = {}
	for i, r in ipairs(changelog.RELEASES) do
		releases[i] = {
			anchor = "v" .. r.version:lower():gsub("[^%w]+", "-"),
			version = r.version, date = r.date, thanks = r.thanks, changes = r.changes,
		}
	end
	return view.page(req, gamename .. " Changelog", "community/changelog", {
		gamename = gamename,
		releases = releases,
	}, { layout = "minimal", nav = false, body_class = "help" })
end

return changelog
