# Plan: 3.1 — the new layout and the hotbar

Status: **in progress** — version **3.1** (started after 3.0.0 with `view.GAME_VERSION =
"3.1.0-dev"`, `DK_VERSION "3.1.0-dev"` and a new top changelog entry `version = "3.1.0",
date = "unreleased"`). Three steps: **Y1** the frame, **Y2** the stage, **Y3** the hotbar.

Decisions taken with the owner: **a wide stage and one sidebar** instead of three columns;
the Towns and Functions panels go (the header's links, a Travel dialog); **one layout for
every theme** (Retro keeps its pictures wherever their heading still exists; the Towns and
Functions pictures go unused, their files stay); the fight menu becomes a **hotbar**: 1 is
always Attack, 0 always Run, and the player puts their other actions in 2-9.

## Goals

- **The middle is used.** What the player is doing fills the stage: the compass and where
	they are, the town's services, the fight.
- **Nothing is legacy-shaped for its own sake.** No list of links in a box: the game's
	functions are the header's links; travel is a list of the towns on the map with their
	cost, where travelling is offered.
- **Keys for fights.** 1 to 9 and 0 press the fight's actions; the arrangement is the
	player's and stays put (muscle memory): an action never moves unless the player moves it.
- **Everything as before underneath.** Pages work without JavaScript; the live client,
	scenes, dialogs, tooltips and the event stream keep working; GETs stay pure.

## Y1: the frame

- **Header** (`layout/main.html`): the logo; the game's links (Inventory, Hotbar, News,
	Forum when there is one, Help, Admin for admins) and the account's (Change Password, Log
	Out); logged out, Log In, Register and Help. Retro draws its pictures for Log Out, Log In,
	Register and Help as before.
- **Two columns**: the stage (`.dk-stage`: the `loc` region, then `main`) and the sidebar
	(`aside.dk-side`, region `side`: Character, Inventory, Fast Spells, the online count and
	the chat, as the right column had them). Narrow windows stack them, the stage first.
- **Regions**: `left` and `right` go; `towns` and `functions` go; `loc` moves into the
	stage; `side` holds `charpanel`, `invpanel`, `spellpanel`, `online-count`, `chat`.
- **Travel**: `GET /travel` lists the towns on the player's map (the one they are in
	marked, the TP each costs, the ones they can't afford greyed), each a `POST /travel/<id>`
	button as before; a fighting player is sent to the fight. Opened in a dialog
	(`data-modal`) from the location panel and the town; its forms carry
	`data-modal-leave` (new in `modal.js`: the dialog closes and the form goes as the page's
	own), so the arrival's scene plays.

## Y2: the stage

- **Location panel** (`layout/place.html`, region `loc`): the compass (not while fighting)
	beside where the player is ("In Midworld", "Exploring", "Fighting"), the coordinates, the
	map and Travel. A step changes only this region (no fade: `main` stays the same).
- **Town** (`home/town.html`): the town's title, then its services as large tiles (the Inn
	with its price, the Shop, the Map Store, Travel with the number of towns on the map), the
	news, who's online and the chat.
- **Exploring** (`home/explore.html`): a line about walking on, who's online and the chat
	(on the stage, as in town, instead of the sidebar).
- The legacy messages that sent the player to "the direction buttons on the left" say "the
	compass"; the help pages describe the new layout.

## Y3: the hotbar

- **Model** (schema version 17): `user_hotbar (user_id, kind, ref_id, slot)`: every action
	the player has met (`kind` `spell` with a spells id, or `item` with an items id: gear
	that casts, or a consumable), on the bar (`slot` 2-9) or off it (`slot` NULL). Attack (1)
	and Run (0) are fixed and not stored.
- **Actions** (`lib/hotbar.lua`): what the fight menu offers besides Attack and Run, in
	its order: the equipped gear that casts (slot order), the fight spells known, the fight
	consumables in the bag (bag order).
- **The bar** (`hotbar.arrange`): the stored slots; then each action the player hasn't met
	goes into the first free slot (2-9), or off the bar when none is free. A stored action
	that isn't available now (a consumable used up, gear not worn, a spell forgotten) keeps
	its slot, greyed. Pure: GET pages show this without writing it.
- **Settling** (`hotbar.settle`): when a fight begins (`encounter.begin`) the arrangement
	is written, so it can't shift during the fight or later.
- **The fight menu**: one row of ten slots, `1` Attack ... `9`, `0` Run, each with its key;
	empty slots dashed. The actions off the bar follow under "More" without keys. A locked
	turn shows Continue, which any number key presses.
- **Keys** (`public/js/hotbar.js`): 1-9 and 0 press the slot's button on the fight page,
	unless a field has the keyboard, a modifier is held, a dialog is open or the button is
	disabled (a round playing).
- **Arranging** (`GET/POST /hotbar`, not while fighting): the ten slots, each of 2-9 with a
	list of the actions (and "Empty"); Save writes every slot (the rest go off the bar), Reset
	forgets the arrangement (the next fight fills the bar again). With JavaScript the actions
	can be dragged onto the slots (and between them), which fills the lists and saves.

## Tests

`tests/e2e/hotbar.sh` (filling, settling, saving, greyed slots, the fight page's keys and
More row, the page while fighting), `tests/e2e/migrate.sh` (step 17), the layout's tests
updated (`town.sh`, `live_wire.sh`, `fight_api.sh`, `tips.sh`, ...), `tests/browser/client.js`
(a number key plays a round; the travel dialog).
