-- routes/fight.lua :: fighting, victory, item drops, death (port of legacy fight.php).
--   GET/POST /fight   fight() -- POST buttons: fight | spell=<id> (a spell's icon button; the
--                     form before 2.3.1 sent spell=Spell + userspell=<id>, still accepted) |
--                     item=<items id> (a consumable's icon button; the form before 2.4 sent
--                     item=Use Item + useritem=<id>, still accepted) | use_gear=<user_items
--                     id> (an equipped item that casts a spell: a charge instead of MP) |
--                     run | continue (a turn a status blocks); fight and run are the Attack
--                     and Run icon buttons (fight=Fight, run=Run: only the name counts)
--   GET      /victory victory()
--   GET/POST /drop    drop()  -- POST: take (+ discard: a bag entry to make room) | leave
--   GET      /dead    dead()
-- The fight is a model loaded and saved once per request (fight/state.lua); a POST plays at
-- most one round of the pipeline (fight/round.lua), whose dice and formulas live in
-- fight/combat.lua. This module checks the player's choice, plays it and saves; how a fight
-- begins (on a map move) and ends (paid in the winning round) is fight/encounter.lua.
-- GETs change nothing (docs/APP.md "Pure GETs"): GET /fight shows the fight with its last
-- round's lines, as the POST that played it did; GET /victory shows the rewards paid.
--
-- The JSON fight API (docs/APP.md "Fight API"; public/js/fight.js): the same routes, asked
-- with Accept: application/json, run the same code and answer { events, fragments, round,
-- redirect, url, title, stale } instead of the page (a redirect is a field, not a 302:
-- fetch would follow it and lose the round's events), or { error } instead of an error
-- page. Every fight form carries the round it was shown at: a POST /fight with another
-- round (a second click, an older tab) plays nothing and shows the fight as it is now.
local act = require("fight.act")
local auth = require("lib.auth")
local encounter = require("fight.encounter")
local events = require("fight.events")
local game = require("lib.game")
local inventory = require("lib.inventory")
local items = require("lib.items")
local json = require("lib.json")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")
local tips = require("lib.tips")
local view = require("lib.view")

local rand = php.rand

-- An error: the page (html: trusted HTML, by default the text escaped), or { error = text }.
local function error_page(req, text, html)
	if view.wants_json(req) then return view.json({ error = text }) end
	return view.message(req, "Error", html or dk.html(text))
end

-- A page of the fight, or its fragments (view.fragment_page) with the fields of t.
local function show(req, title, template, ctx, t)
	if view.wants_json(req) then
		t = t or {}
		t.events = t.events or json.array()
		return view.fragment_page(req, title, template, ctx, t)
	end
	return view.page(req, title, template, ctx)
end

-- A redirect, or { redirect = url } with the fields of t.
local function go(req, url, t)
	if not view.wants_json(req) then return view.redirect(url) end
	t = t or {}
	t.redirect = url
	t.events = t.events or json.array()
	return view.json(t)
end

-- The fight menu's item buttons: consumables in the bag usable in fights, one per item with
-- the quantity over all its stacks: { id, name, qty, label, icon (URL), short (its can_use
-- refuses now: greyed out; the server checks again), item (the row), tip (its tooltip) }.
local function usable_items(user, f)
	local out, by_id = {}, {}
	for _, e in ipairs(inventory.bag(user.id)) do
		if items.usable(e.item, "fight") then
			local line = by_id[e.item.id]
			if not line then
				line = { id = e.item.id, name = e.item.name, qty = 0, icon = items.icon_url(e.item), item = e.item,
					short = not act.can_use(f, e.item) }
				by_id[e.item.id] = line
				out[#out + 1] = line
			end
			line.qty = line.qty + e.qty
		end
	end
	for _, line in ipairs(out) do
		line.label = line.name .. " (x" .. line.qty .. ")"
		line.tip = tips.consumable(line.item, line.qty)
	end
	return out
end

-- The fight menu's gear buttons: equipped items that cast a spell, in slot order: { id
-- (the user_items id), name, charges, max, label ("Wand (3/5 charges)"), icon (URL), short
-- (no charge left, or the spell can't be cast: greyed out), tip (its tooltip) }.
local function gear_buttons(user)
	local out = {}
	local eq = inventory.equipped(user.id)
	for _, slot in ipairs(inventory.SLOTS) do
		local e = eq[slot]
		if e and items.casts(e.item) then
			local spell = items.spell(e.item)
			local charges = math.min(e.charges, e.item.charges)
			out[#out + 1] = { id = e.id, name = e.item.name, charges = charges, max = e.item.charges,
				label = e.item.name .. " (" .. charges .. "/" .. e.item.charges .. " charges)", icon = items.icon_url(e.item),
				short = charges < 1 or not (spell and spells.usable(spell, "fight")), tip = tips.gear(e) }
		end
	end
	return out
end

-- name (turns left) of each status of combatant c, for the page
local function status_list(c)
	local out = {}
	for _, s in ipairs(c.statuses) do out[#out + 1] = { name = s.row.name, turns = s.turns_left } end
	return out
end

-- Whether the page shows enemy c's MP: only a monster with spells (what it means to the
-- player).
local function shows_mp(c)
	return #monsters.loadout(c.row).spells > 0
end

-- What the fight page shows of the fight: the enemies of the wave, the allies, statuses.
local function view_of(f)
	local p = state.player(f)
	local enemies, allies = {}, {}
	for _, c in ipairs(state.side(f, "enemy", true)) do
		local mp = shows_mp(c)
		enemies[#enemies + 1] = { id = c.id, name = c.row.name, hp = c.hp, maxhp = c.maxhp, mp = mp and c.mp or nil,
			maxmp = mp and c.maxmp or nil, statuses = status_list(c), row = c.row }
	end
	for _, c in ipairs(state.allies(f)) do
		allies[#allies + 1] = { id = c.id, name = c.row.name, hp = c.hp, maxhp = c.maxhp, turns = c.turns_left,
			statuses = status_list(c) }
	end
	return { enemies = enemies, allies = allies, player_id = p.id, player_statuses = status_list(p) }
end

-- The events of round r (fight/events.lua), with its outcome last.
local function round_events(r)
	local list = events.build(r.f.trace, { hide_mp = function(id)
		local c = state.get(r.f, id)
		return not (c and c.row and shows_mp(c))
	end })
	local outcome = r.escaped and "escape" or r.victory and "victory" or r.died and "death"
	if outcome then events.outcome(list, outcome, state.player(r.f).id, r.f.st.charname) end
	return json.array(list)
end

-- The player's choice in a POST's form (nil: none, e.g. a stale form): { kind, spell,
-- item }, plus the bag entry (a consumable) or the equipped entry (gear) it uses; or nil,
-- nil, nil, an error text (a refusal: nothing happens).
local function choice(user, st, f, form)
	-- a status that blocks the action (asleep, recharging, ...) leaves only "Continue"
	if round.locked(f) and (form.run or form.fight or form.spell or form.item or form.use_gear or form.continue) ~= nil then
		return { kind = "continue" }
	elseif form.run ~= nil then
		return { kind = "run" }
	elseif form.fight ~= nil then
		return { kind = "attack" }
	elseif form.spell ~= nil then
		-- the icon button's value, or the old select's (spell=Spell&userspell=<id>)
		local picked = form.userspell
		if picked == nil then picked = form.spell end
		if php.intval(picked) == 0 then return nil, nil, nil, "You must select a spell first. Please go back and try again." end
		-- Validated server-side: an integer id the user knows that exists in spells.
		local spell_id = math.tointeger(tonumber(picked))
		local spell = spell_id and spells.knows(user, spell_id) and spells.get(spell_id) or nil
		if not spell then return nil, nil, nil, "You have not yet learned this spell. Please go back and try again." end
		if st.currentmp < spell.mp then
			return nil, nil, nil, "You do not have enough Magic Points to cast this spell. Please go back and try again."
		end
		return { kind = "spell", spell = spell }
	elseif form.use_gear ~= nil then
		-- an equipped item that casts a spell: a charge instead of MP, the turn like an item
		local entry_id = math.tointeger(tonumber(form.use_gear))
		local gear = entry_id and inventory.entry(user.id, entry_id)
		if not gear or not gear.equipped or not items.casts(gear.item) then
			return nil, nil, nil, "You do not have this item equipped. Please go back and try again."
		end
		local spell = items.spell(gear.item)
		if not spell then return nil, nil, nil, act.CANNOT.item end
		if gear.charges < 1 then
			return nil, nil, nil, "The " .. gear.item.name .. " has no charges left. Rest at an inn to recharge it."
		end
		return { kind = "gear", item = gear.item, spell = spell }, nil, gear
	elseif form.item ~= nil then
		-- a consumable from the bag: costs the turn like a spell (refusals cost nothing); the
		-- icon button's value, or the old select's (item=Use Item&useritem=<id>)
		local picked = form.useritem
		if picked == nil then picked = form.item end
		if php.intval(picked) == 0 then return nil, nil, nil, "You must select an item first. Please go back and try again." end
		-- validated server-side: an integer item id with a stack in the user's bag
		local item_id = math.tointeger(tonumber(picked))
		local entry = item_id and inventory.find(user.id, item_id)
		if not entry then return nil, nil, nil, "You do not have this item. Please go back and try again." end
		return { kind = "item", item = entry.item }, entry
	end
	-- nothing chosen ("continue" on a turn no status blocks): nothing is played
	return nil
end

-- The fight page of fight f (in progress, or as it ended in a death): its combatants, the
-- lines of its last round (lines: encounter.lines), and the commands with the round they
-- carry. opts: stale (the note), events (the JSON API's).
local function fight_page(req, f, lines, opts)
	local user = req.user
	local page = { yourturn = lines.yourturn, allyturn = lines.allyturn, monsterturn = lines.monsterturn,
		roundend = lines.roundend, stale = opts.stale, dead = f.outcome == "death" }
	local shown = view_of(f)
	for k, v in pairs(shown) do page[k] = v end
	local first = shown.enemies[1]
	for _, e in ipairs(shown.enemies) do
		if e.hp > 0 then first = e break end
	end
	page.monstername, page.monsterhp, page.monstermp = first.name, first.hp, first.mp
	page.monsterid, page.monstermaxhp, page.monstermaxmp = first.id, first.maxhp, first.maxmp
	page.monster = first.row   -- its tooltip
	if not page.dead then
		page.locked = round.locked(f)
		local weapon = inventory.equipped(user.id).weapon
		page.attack_tip = tips.attack(f.st.attackpower, weapon and weapon.item.name)
		page.run_tip = tips.run()
		page.spells = spells.buttons(spells.known(user, "fight"), f.st.currentmp)
		page.items = usable_items(user, f)
		page.gear = gear_buttons(user)
		page.round = f.round
	end
	return show(req, "Fighting", "fight/fight", page, { events = opts.events or json.array(), round = page.round,
		stale = opts.stale or nil })
end

local NO_MONSTER = "There are no monsters in this area. Please contact the game administrator."

local function fight(req)
	local user = req.user
	local post = req.method == "POST"
	local form = post and req.form or {}
	-- the round the form was shown at (absent: a form from before 2.3, or a GET)
	local sent = form.round ~= nil and php.intval(form.round) or nil
	local st = game.player(user)
	local f = state.load(user, st)
	if user.currentaction ~= "Fighting" then
		-- the fight that just ended: a death shows as it ended, a victory has its own page
		if f and f.outcome == "death" and #state.side(f, "enemy", true) > 0 and not post then
			return fight_page(req, f, encounter.lines(f.log), {})
		end
		if f and f.outcome == "victory" and not post then return go(req, "/victory") end
		-- a form of a fight that is over: the game as it is now
		if sent then return go(req, "/", { stale = true }) end
		return error_page(req, "Cheat attempt detected. Get a life, loser.", "Cheat attempt detected.<br><br>Get a life, loser.")
	end
	if f and f.outcome ~= "" then f = nil end

	-- A fighting player without a fight to show (its enemies are gone, or a database from
	-- before 3.0 slipped through): a POST begins a new encounter where they stand.
	if not f or #state.side(f, "enemy", true) == 0 then
		if not post then return error_page(req, NO_MONSTER) end
		if not encounter.begin(user.id) then return error_page(req, NO_MONSTER) end
		return go(req, "/fight")
	end
	-- A form shown at another round than the fight's (a second click, an older tab) plays
	-- nothing: the fight page as it is, with a note.
	local stale = sent ~= nil and sent ~= f.round
	if post and state.won(f) then
		-- a fight won without its payout (a database from before 3.0): paid now
		encounter.win(user, f, nil)
		return go(req, "/victory", { stale = stale or nil })
	end
	if stale or not post then return fight_page(req, f, encounter.lines(f.log), { stale = stale }) end
	f.rand = rand
	f.max_allies = game.control().max_allies or 1
	local a, entry, gear, err = choice(user, st, f, form)
	if err then return error_page(req, err) end
	if not a then return fight_page(req, f, encounter.lines(f.log), {}) end

	if view.wants_json(req) then f.trace = {} end
	local r = round.play(f, a)
	-- refusal texts may come from content files and admin overrides: escaped
	if r.refused then return error_page(req, r.refused) end
	if entry then inventory.take(entry, 1) end
	if gear then inventory.spend_charge(gear) end
	f = r.f
	local evs = f.trace and round_events(r) or json.array()
	if r.escaped then
		-- fixed: legacy always let the player escape (a failed run's damage was never saved,
		-- and a fatal blow left them 'Exploring' at 0,0) and kept the fight state.
		state.clear(user.id)
		encounter.save_player(user.id, f.st)
		dk.db:exec("UPDATE users SET currentaction = 'Exploring' WHERE id = ?", user.id)
		return go(req, "/", { events = evs })
	elseif r.victory then
		encounter.save_player(user.id, f.st)
		encounter.win(user, f, r)
		return go(req, "/victory", { events = evs })
	elseif r.died then
		encounter.die(user, r)
		return fight_page(req, f, encounter.lines(f.log), { events = evs })
	end
	f.round = f.round + 1
	f.log = encounter.log_of(r)
	state.save(f)
	encounter.save_player(user.id, f.st)
	return fight_page(req, f, encounter.lines(f.log), { events = evs })
end

local function victory(req)
	local f = state.load(req.user, game.player(req.user))
	if f and f.outcome == "victory" then
		local title, ctx = encounter.victory_page(f.result)
		return show(req, title, "fight/victory", ctx)
	end
	if req.user.currentaction == "Fighting" then return go(req, "/fight") end
	return go(req, "/")
end

-- The pending drop (users.dropcode: an items.id), or nil.
local function pending_drop(user)
	if user.dropcode == 0 then return nil end
	return items.get(user.dropcode)
end

local function drop_page(req, drop, ctx)
	local user = req.user
	local bag = inventory.bag(user.id)
	ctx = ctx or {}
	ctx.drop = drop
	ctx.attributes = items.attributes(drop)
	local room = inventory.room(drop, bag, inventory.size())
	ctx.full = room == 0
	if ctx.full then
		-- what could make room: bag items that count against the size (not quest items)
		ctx.discardable = {}
		for _, e in ipairs(bag) do
			if e.item.category ~= "quest" then ctx.discardable[#ctx.discardable + 1] = e end
		end
	end
	return show(req, "Item Drop", "fight/drop", ctx)
end

local function drop_get(req)
	local drop = pending_drop(req.user)
	if not drop then return go(req, "/") end
	return drop_page(req, drop)
end

-- POST /drop: "take" puts the item into the bag (after discarding bag entry `discard`
-- when the bag is full); "leave" gives it up.
local function drop_post(req)
	local user = req.user
	local drop = pending_drop(user)
	if not drop then return go(req, "/") end
	if req.form.leave ~= nil then
		dk.db:exec("UPDATE users SET dropcode = 0 WHERE id = ?", user.id)
		return go(req, "/")
	end
	if req.form.take == nil then return drop_page(req, drop) end
	local discard_id = php.intval(req.form.discard)
	local discarded
	if discard_id ~= 0 then
		local e = inventory.entry(user.id, discard_id)
		if not e or e.equipped or e.item.category == "quest" then
			return error_page(req, "Please go back and select an item from your bag to discard.")
		end
		inventory.take(e)
		discarded = e
	end
	if not inventory.add(user.id, drop, 1) then
		return drop_page(req, drop, { error = "Your bag is full. Choose an item to discard first, or leave the " ..
			drop.name .. "." })
	end
	dk.db:exec("UPDATE users SET dropcode = 0 WHERE id = ?", user.id)
	return show(req, "Item Drop", "fight/drop_taken", { drop = drop, discarded = discarded })
end

-- legacy dead() built this page but never displayed it; deaths are reported on the
-- fight page. Kept as a read-only page.
local function dead(req)
	return show(req, "You Have Died", "fight/dead", {})
end

return function(r)
	r:get("/fight", auth.game, fight)
	r:post("/fight", auth.game, fight)
	r:get("/victory", auth.game, victory)
	r:get("/drop", auth.game, drop_get)
	r:post("/drop", auth.game, drop_post)
	r:get("/dead", auth.game, dead)
end
