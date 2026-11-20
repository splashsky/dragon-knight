-- community/changelog.lua :: GET /changelog, the game's version history. Everything up to
-- 1.1.11 is the original changelog.txt from dragon.se7enet.com (via the Internet Archive),
-- kept verbatim; newer releases go on top in the same style.
local game = require("lib.game")
local view = require("lib.view")

local changelog = {}

changelog.RELEASES = {
	{
		version = "2.3.0", date = "unreleased",
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
