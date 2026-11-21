# Plan: 3.1 — the hotbar

Status: **done** (unreleased) — version **3.1** (started after 3.0.0 with
`view.GAME_VERSION = "3.1.0-dev"`, `DK_VERSION "3.1.0-dev"` and a new top changelog entry
`version = "3.1.0", date = "unreleased"`).

3.1 began as a layout redesign (a wide stage and one sidebar, the header's links instead of
the Functions box, a location panel with the compass, a travel dialog, town services as
tiles) and the hotbar. The redesign was built, reviewed and **reverted at the owner's
request**: the game keeps 3.0's three columns (commits `34bc969`, reverted in the commit
that renamed this plan). The hotbar stays, its link in the Functions box.

Decision taken with the owner: the fight menu becomes a **hotbar**: 1 is always Attack, 0
always Run, and the player puts their other actions in 2-9.

## Goals

- **Keys for fights.** 1 to 9 and 0 press the fight's actions; the arrangement is the
	player's and stays put (muscle memory): an action never moves unless the player moves it.
- **Everything as before underneath.** Pages work without JavaScript; the live client,
	scenes, dialogs, tooltips and the event stream keep working; GETs stay pure.

## The hotbar — ✅ done

**As implemented** (`docs/APP.md` "Hotbar"): as designed, plus: an action met while the bar
was full stays off it even when a key frees later (it was met: only the player moves it);
the Reset button is `forget` (a control named `reset` hides the form's `reset()`, which the
live client calls after a POST); `scene.js` doesn't fade `/hotbar` into `/hotbar` (a drag
saves in place); `dk install --force` drops `user_hotbar` too.

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
- **Arranging** (`GET/POST /hotbar`, linked from the Functions box; not while fighting):
	the ten slots, each of 2-9 with a list of the actions (and "Empty"); Save writes every
	slot (the rest go off the bar), Reset forgets the arrangement (the next fight fills the
	bar again). With JavaScript the actions can be dragged onto the slots (and between them),
	which fills the lists and saves.

## Tests

`tests/e2e/hotbar.sh` (filling, settling, saving, greyed slots, the fight page's keys and
More row, the page while fighting), `tests/e2e/migrate.sh` (step 17), the fight tests'
button markup (`fight.sh`, `fight_api.sh`, `tips.sh`, `wand.sh`, ...),
`tests/browser/client.js` (a number key plays a round, not while typing; a drag saves).
