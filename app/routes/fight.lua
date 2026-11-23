-- routes/fight.lua :: fighting, victory, item drops, death (port of legacy fight.php).
--   GET/POST /fight   fight() -- POST buttons: fight | spell=<id> (a spell's icon button; the
--                     form before 2.3.1 sent spell=Spell + userspell=<id>, still accepted) |
--                     item=<items id> (a consumable's icon button; the form before 2.4 sent
--                     item=Use Item + useritem=<id>, still accepted) | use_gear=<user_items
--                     id> (an equipped item that casts a spell: a charge instead of MP) |
--                     guard | run | continue (a turn a status blocks: it ends at the clock's
--                     next tick, so nothing is played); fight, guard and run are the Attack,
--                     Guard and Run icon buttons (fight=Fight, guard=Guard, run=Run: only the
--                     name counts); target=<combatant id> (the target picker's radio group: an
--                     enemy or an object the actions aim at from now on)
--   GET      /victory victory()
--   GET/POST /drop    drop()  -- POST: take (+ discard: a bag entry to make room) | leave
--   GET      /dead    dead()
-- The fight is a model loaded and saved once per request (fight/state.lua) and runs on the
-- game's clock: a POST first catches it up to now (fight/encounter.lua encounter.advance,
-- what the server's tick does: statuses and allies count the ticks, a turn that ran out is
-- guarded), then plays at most one round of the pipeline (fight/round.lua), whose dice and
-- formulas live in fight/combat.lua. This module checks the player's choice, plays it and
-- saves; how a fight begins (on a map move) and ends (paid in the winning round) is
-- fight/encounter.lua. GETs change nothing (docs/APP.md "Pure GETs"): GET /fight shows the
-- fight as the last POST or tick left it, with its lines since the player's last command,
-- and the turn's deadline for the page's timer; GET /victory shows the rewards paid.
--
-- Smooth fights (docs/APP.md "Fight events"; public/js/fight.js): a live request (the live
-- client) gets the round's events with its answer, as an `events fight` frame (on the page
-- or on the redirect the server follows), which fight.js plays before the page's regions
-- apply. Every fight form carries the round it was shown at: a POST /fight with another
-- round (a second click, an older tab, a page from before the turn ran out) plays nothing
-- and shows the fight as it is now.
-- A round that ends the fight (a victory, a death, a getaway) adds a scene after its
-- events (lib/scene.lua; public/js/scene.js): the fight fades out into the page it ends on.
local act = require("fight.act")
local auth = require("lib.auth")
local clock = require("lib.clock")
local encounter = require("fight.encounter")
local engine = require("fight.engine")
local events = require("fight.events")
local fields = require("fight.fields")
local game = require("lib.game")
local hotbar = require("lib.hotbar")
local inventory = require("lib.inventory")
local items = require("lib.items")
local scene = require("lib.scene")
local speech = require("fight.speech")
local json = require("lib.json")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local schema = require("lib.content.schema")
local spells = require("lib.spells")
local state = require("fight.state")
local tips = require("lib.tips")
local view = require("lib.view")

local rand = php.rand

-- An error page (html: trusted HTML, by default the text escaped).
local function error_page(req, text, html)
	return view.message(req, "Error", html or dk.html(text))
end

-- The answer's events for the live client: { { kind = "fight", json } } (nil: none).
local function fight_events(req, evs)
	if not req.live or not evs or #evs == 0 then return nil end
	return { { kind = "fight", json = json.encode(evs) } }
end

-- A page of the fight (its rounds' events come with the redirects to it: go).
local function show(req, title, template, ctx)
	return view.page(req, title, template, ctx)
end

-- A redirect; t.events: the round's, carried to the page it lands on (main.lua follows
-- a live request's redirects on the server); t.scene: { kind, title, detail [, page =
-- true] } after them (lib/scene.lua).
local function go(req, url, t)
	local res = view.redirect(url)
	res.events = fight_events(req, t and t.events)
	if t and t.scene then scene.add(req, res, t.scene[1], t.scene[2], t.scene[3], t.scene.page) end
	return res
end

-- The name of the enemy still standing (the first of them), for a scene's details.
local function foe(f)
	local c = state.side(f, "enemy", true)[1]
	return c and c.row.name or "monster"
end

-- A victory's scene details: who fell and what it paid (encounter.win's result).
local function victory_detail(res)
	local s = "You defeated the " .. (res.defeated or "monster") .. ": +" .. php.number_format(res.exp or 0) ..
		" experience, +" .. php.number_format(res.gold or 0) .. " gold."
	if res.levelup then s = s .. " You gained a level!" elseif res.dropped then s = s .. " It left something behind." end
	return s
end

-- The fight menu's item buttons: consumables in the bag usable in fights, one per item with
-- the quantity over all its stacks: { kind = "item", key (its hotbar key), id, name, qty,
-- label, icon (URL), short (its can_use refuses now: greyed out; the server checks again),
-- item (the row), tip (its tooltip) }.
local function usable_items(user, f)
	local out, by_id = {}, {}
	for _, e in ipairs(inventory.bag(user.id)) do
		if items.usable(e.item, "fight") then
			local line = by_id[e.item.id]
			if not line then
				line = { kind = "item", key = hotbar.key("item", e.item.id), id = e.item.id, name = e.item.name, qty = 0,
					icon = items.icon_url(e.item), item = e.item, short = not act.can_use(f, e.item) }
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

-- The fight menu's gear buttons: equipped items that cast a spell, in slot order: { kind =
-- "gear", key (its hotbar key: the item's), id (the user_items id), name, charges, max,
-- label ("Wand (3/5 charges)"), icon (URL), short (no charge left, or the spell can't be
-- cast: greyed out), tip (its tooltip) }.
local function gear_buttons(user)
	local out = {}
	local eq = inventory.equipped(user.id)
	for _, slot in ipairs(inventory.SLOTS) do
		local e = eq[slot]
		if e and items.casts(e.item) then
			local spell = items.spell(e.item)
			local charges = math.min(e.charges, e.item.charges)
			out[#out + 1] = { kind = "gear", key = hotbar.key("item", e.item.id), id = e.id, name = e.item.name,
				charges = charges, max = e.item.charges,
				label = e.item.name .. " (" .. charges .. "/" .. e.item.charges .. " charges)", icon = items.icon_url(e.item),
				short = charges < 1 or not (spell and spells.usable(spell, "fight")), tip = tips.gear(e) }
		end
	end
	return out
end

-- The fight menu's spell buttons (spells.buttons), with their kind, hotbar key and tooltip.
local function spell_buttons(user, mp)
	local out = spells.buttons(spells.known(user, "fight"), mp)
	for _, b in ipairs(out) do b.kind, b.key, b.tip = "spell", hotbar.key("spell", b.id), tips.spell(b.spell) end
	return out
end

-- What an action on the bar but not at hand lacks, for its greyed slot.
local function missing(a)
	if a.kind == "spell" then return "not known" end
	if a.item.category == "consumable" then return "none left" end
	return "not worn"
end

-- The hotbar (lib/hotbar.lua) from the fight menu's buttons (gear, spells, items, in that
-- order): slots 2-9, each { n, button } (its hotkey n), { n, gone = action, why } (an
-- action of the bar's not at hand) or { n } (empty); and the buttons off the bar ("More").
local function hotbar_view(user, buttons)
	local by_key, keys = {}, {}
	for _, b in ipairs(buttons) do
		if not by_key[b.key] then
			by_key[b.key] = b
			keys[#keys + 1] = b.key
		end
	end
	local slots = hotbar.arrange(user.id, keys)
	local bar, shown = {}, {}
	for n = hotbar.FIRST, hotbar.LAST do
		local key = slots[n]
		local b = key and by_key[key]
		local gone = key and not b and hotbar.describe(key)
		if b then
			b.hotkey = n
			shown[b] = true
			bar[#bar + 1] = { n = n, button = b }
		elseif gone then
			bar[#bar + 1] = { n = n, gone = gone, why = missing(gone) }
		else
			bar[#bar + 1] = { n = n }
		end
	end
	local more = {}
	for _, b in ipairs(buttons) do
		if not shown[b] then more[#more + 1] = b end
	end
	return bar, more
end

-- name, time left ("30s": its ticks left, nil without a limit) and icon of each status of
-- combatant c, for the page
local function status_list(c)
	local out = {}
	for _, s in ipairs(c.statuses) do
		out[#out + 1] = { name = s.row.name, left = s.ticks_left and events.left(s.ticks_left),
			icon = schema.entity_icon("statuses", s.row.icon) }
	end
	return out
end

-- Whether the page shows enemy c's MP: only a monster with spells (what it means to the
-- player).
local function shows_mp(c)
	return #monsters.loadout(c.row).spells > 0
end

-- The battlefield line: each field up with its icon, and its tooltip (a spell's says the
-- time it has left).
local function battlefield(f)
	local out = {}
	for _, x in ipairs(fields.up(f)) do
		out[#out + 1] = { key = x.key, name = x.row.name, icon = schema.entity_icon("fields", x.row.icon),
			tip = tips.field(x.row, x.ticks and events.left(x.ticks)) }
	end
	return out
end

-- What the fight page shows of the fight: the enemies of the wave, the allies, the objects
-- on the field (and the side each stands over: "over you", "over the Goblin"), statuses, the
-- battlefield, and the target (engine.target: its id) with whether there is a choice (more
-- than one enemy or object to aim at: the target picker).
local function view_of(f)
	local p = state.player(f)
	local enemies, allies, objects = {}, {}, {}
	for _, c in ipairs(state.side(f, "enemy", true)) do
		local mp = shows_mp(c)
		enemies[#enemies + 1] = { id = c.id, name = c.row.name, hp = c.hp, maxhp = c.maxhp, mp = mp and c.mp or nil,
			maxmp = mp and c.maxmp or nil, statuses = status_list(c), row = c.row,
			icon = schema.entity_icon("monsters", c.row.icon) }
	end
	for _, c in ipairs(state.allies(f)) do
		allies[#allies + 1] = { id = c.id, name = c.row.name, hp = c.hp, maxhp = c.maxhp,
			left = c.ticks_left and events.left(c.ticks_left),
			statuses = status_list(c), icon = schema.entity_icon("summons", c.row.icon) }
	end
	local foe = state.enemies(f)[1]
	for _, c in ipairs(state.objects(f)) do
		objects[#objects + 1] = { id = c.id, name = c.row.name, hp = c.hp, maxhp = c.maxhp, row = c.row,
			over = c.over == "player" and "over you" or ("over the " .. (foe and foe.row.name or "monster")),
			statuses = status_list(c), icon = schema.entity_icon("interactables", c.row.icon) }
	end
	local target = engine.target(f, p)
	return { enemies = enemies, allies = allies, objects = objects, player_id = p.id, player_statuses = status_list(p),
		battlefield = battlefield(f), target = target and target.id,
		choices = #state.enemies(f) + #objects }
end

-- The events of what this request did to fight f (its trace: the clock's ticks it caught
-- up, then its round; fight/events.lua), with the outcome ("victory", "death", "escape")
-- last; nil when it wasn't traced.
local function fight_trace(f, outcome)
	if not f.trace then return nil end
	local list = events.build(f.trace, { hide_mp = function(id)
		local c = state.get(f, id)
		return not (c and c.row and shows_mp(c))
	end })
	if outcome then events.outcome(list, outcome, state.player(f).id, f.st.charname) end
	return json.array(list)
end

-- The player's choice in a POST's form (nil: none, e.g. "continue"): { kind, spell, item },
-- plus the bag entry (a consumable) or the equipped entry (gear) it uses; or nil, nil,
-- nil, an error text (a refusal: nothing happens).
local function choice(user, st, f, form)
	if form.run ~= nil then
		return { kind = "run" }
	elseif form.fight ~= nil then
		return { kind = "attack" }
	elseif form.guard ~= nil then
		return { kind = "guard" }
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
			return nil, nil, nil, "The " .. gear.item.name .. " has no charges left." ..
				(items.rechargeable(gear.item) and " Rest at an inn to recharge it." or "")
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
-- lines of its last round and the note about the last command (lines: encounter.lines),
-- and the commands with the round they carry.
-- A part's lines for the page: { text, speech (a monster speaking: fight/speech.lua) }.
local function page_lines(list)
	local out = {}
	for i, l in ipairs(list or {}) do
		if l:sub(1, 1) == speech.MARK then out[i] = { text = l:sub(2), speech = true } else out[i] = { text = l } end
	end
	return out
end

local function fight_page(req, f, lines)
	local user = req.user
	local log = {}
	for i, p in ipairs(lines.paragraphs) do log[i] = { class = "fight-" .. p.part, lines = page_lines(p.lines) } end
	local page = { log = log, stale = lines.stale, note = lines.note, dead = f.outcome == "death" }
	if page.dead and (f.result.taunt or "") ~= "" then page.taunt = { by = f.result.taunt_by or "", text = f.result.taunt } end
	local shown = view_of(f)
	for k, v in pairs(shown) do page[k] = v end
	local first = shown.enemies[1]
	for _, e in ipairs(shown.enemies) do
		if e.hp > 0 then first = e break end
	end
	page.monstername, page.monsterhp, page.monstermp = first.name, first.hp, first.mp
	page.monsterid, page.monstermaxhp, page.monstermaxmp = first.id, first.maxhp, first.maxmp
	page.monster = first.row   -- its tooltip
	page.monstericon = first.icon   -- its portrait (nil: none)
	if not page.dead then
		page.locked = round.locked(f)
		-- the target picker (a radio group in the command form): with more than one choice
		page.pick = not page.locked and shown.choices > 1
		local weapon = inventory.equipped(user.id).weapon
		page.attack_tip = tips.attack(f.st.attackpower, weapon and weapon.item.name)
		page.guard_tip = tips.guard()
		page.run_tip = tips.run()
		local buttons = gear_buttons(user)
		for _, list in ipairs({ spell_buttons(user, f.st.currentmp), usable_items(user, f) }) do
			for _, b in ipairs(list) do buttons[#buttons + 1] = b end
		end
		page.bar, page.more = hotbar_view(user, buttons)
		page.round = f.round
		-- the turn's timer (public/js/fight.js; display only: the server's tick plays the
		-- timeout): when it runs out (a blocked turn: at the next tick; a fight not on the
		-- clock yet starts on it when next played) and the server's time
		page.now = clock.now()
		local tick, deadline = f.tick, f.deadline
		if tick == 0 then tick = clock.tick(page.now); deadline = tick + round.TURN end
		page.turn_ends = clock.tick_start(page.locked and tick + 1 or deadline)
	end
	return show(req, "Fighting", "fight/fight", page)
end

local NO_MONSTER = "There are no monsters in this area. Please contact the game administrator."

-- A command that played nothing (refused, or from an older page): the fight page says so,
-- above its commands. The refusals' texts (some from content files) were written for an
-- error page of their own ("Please go back and try again."); on the fight page there is
-- nothing to go back to. (The events: what catching the fight up did.)
local function note(req, f, kind, text)
	if text then text = text:gsub("%s*Please go back and try again%.%s*$", "") end
	dk.db:exec("UPDATE fights SET log = ? WHERE user_id = ?", encounter.with_note(f.log, kind, text), f.user_id)
	return go(req, "/fight", { events = fight_trace(f) })
end

-- The fight ended in this request (a round, or the clock caught up): the page it ends on,
-- with the events and the scene.
local function ended(req, f, how)
	if how == "escape" then
		return go(req, "/", { events = fight_trace(f, "escape"),
			scene = { "escape", "You got away", "The " .. foe(f) .. " is left behind." } })
	elseif how == "victory" then
		return go(req, "/victory", { events = fight_trace(f, "victory"),
			scene = { "victory", "Victory!", victory_detail(f.result), page = true } })
	end
	return go(req, "/fight", { events = fight_trace(f, "death"),
		scene = { "death", "You have died", "The " .. foe(f) .. " defeated you. A quarter of your gold is lost." } })
end

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
			return fight_page(req, f, encounter.lines(f.log))
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
	if post and state.won(f) then
		-- a fight won without its payout (a database from before 3.0): paid now
		encounter.win(user, f)
		return go(req, "/victory")
	end
	if not post then return fight_page(req, f, encounter.lines(f.log)) end
	-- Every POST ends on the fight page by a redirect (Post/Redirect/Get): what it did is
	-- saved with the fight (a round's lines, or a note), and GET /fight shows it. First the
	-- fight catches up with the clock (what the server's tick would have done by now), so
	-- a form from before a turn that ran out is stale.
	f.rand = rand
	f.max_allies = game.control().max_allies or 1
	if req.live then f.trace = {} end
	local caught = encounter.advance(user, f, clock.tick(clock.now()))
	f = caught.f
	if caught.died then return ended(req, f, "death") end
	if caught.victory then return ended(req, f, "victory") end
	-- A form shown at another round than the fight's (a second click, an older tab, a turn
	-- that ran out since) plays nothing: the fight page as it is, with a note.
	if sent ~= nil and sent ~= f.round then return note(req, f, "stale") end
	-- a turn a status blocks ends at the next tick: nothing to play now
	if round.locked(f) then return go(req, "/fight", { events = fight_trace(f) }) end
	-- the target picker: an enemy or an object on the field to aim at from now on (anything
	-- else is left alone: the target stays)
	local picked = tonumber(form.target or "")
	picked = picked and math.tointeger(picked)
	if picked and engine.targetable(f, state.get(f, picked)) then f.data.target = picked end
	local a, entry, gear, err = choice(user, f.st, f, form)
	if err then return note(req, f, "note", err) end
	if not a then return go(req, "/fight", { events = fight_trace(f) }) end

	local r = round.play(f, a)
	if r.refused then return note(req, f, "note", r.refused) end
	if entry then inventory.take(entry, 1) end
	if gear and inventory.spend_charge(gear) then
		r.player[#r.player + 1] = "Your " .. gear.item.name .. " is used up."
	end
	f = r.f
	f.log = encounter.log_of(round.lines(r, caught.lines))
	if r.escaped then
		-- fixed: legacy always let the player escape (a failed run's damage was never saved,
		-- and a fatal blow left them 'Exploring' at 0,0) and kept the fight state.
		state.clear(user.id)
		encounter.save_player(user.id, f.st)
		dk.db:exec("UPDATE users SET currentaction = 'Exploring' WHERE id = ?", user.id)
		return ended(req, f, "escape")
	elseif r.victory then
		encounter.save_player(user.id, f.st)
		encounter.win(user, f)
		return ended(req, f, "victory")
	elseif r.died then
		encounter.die(user, f)
		return ended(req, f, "death")
	end
	round.next_turn(f)
	state.save(f)
	encounter.save_player(user.id, f.st)
	return go(req, "/fight", { events = fight_trace(f) })
end

-- The pending drop (users.dropcode: an items.id), or nil.
local function pending_drop(user)
	if user.dropcode == 0 then return nil end
	return items.get(user.dropcode)
end

-- What the drop card offers (fight/drop_offer.html): the item as the shop's purchase shows
-- it (its picture, kind, what it changes against the piece worn in its slot, its effects)
-- and the choices: equip it (gear: into its slot; an accessory into the first empty
-- accessory slot, or with all three taken one choice per slot), put it into the bag, or
-- leave it. A choice that would need bag room the bag hasn't (for the drop, or for the
-- piece it replaces) says so; with a full bag, "Make room" opens the bag (GET /drop/room).
local function drop_offer(user, drop)
	local size, bag = inventory.size(), inventory.bag(user.id)
	local eq = inventory.equipped(user.id)
	local function room_for(item) return inventory.room(item, bag, size) > 0 end
	local o = { drop = drop, icon = items.icon_url(drop), kind = items.category_label(drop),
		bag_room = room_for(drop), equips = {}, effects = {} }
	if items.is_gear(drop) then
		local slots = { drop.slot }
		if drop.slot == "accessory" then
			local free = inventory.free_accessory_slot(user.id)
			slots = free and { free } or inventory.ACCESSORY_SLOTS
		else
			o.old = eq[drop.slot]
		end
		for _, slot in ipairs(slots) do
			local old = eq[slot]
			o.equips[#o.equips + 1] = { slot = slot, label = inventory.LABELS[slot], old = old,
				ok = not old or room_for(old.item), accessory = drop.slot == "accessory" }
		end
		o.description = drop.description
	elseif (drop.description or "") ~= "" then
		o.effects[1] = drop.description
	end
	o.stats = items.compare_view(drop, o.old and o.old.item)
	for _, l in ipairs(items.charge_lines(drop)) do o.effects[#o.effects + 1] = l end
	return o
end

-- The victory page and ctx (fight/victory.html): the rewards, and the drop: its card while
-- it waits (users.dropcode), or what became of it (fights.result.drop_note).
local function victory_page(req, f)
	local title, ctx = encounter.victory_page(f.result)
	local drop = pending_drop(req.user)
	if drop then ctx.offer = drop_offer(req.user, drop) end
	return show(req, title, "fight/victory", ctx)
end

local function victory(req)
	local f = state.load(req.user, game.player(req.user))
	if f and f.outcome == "victory" then return victory_page(req, f) end
	if req.user.currentaction == "Fighting" then return go(req, "/fight") end
	return go(req, "/")
end

-- The won fight, when its page is still there (a drop is offered on it), or nil.
local function won_fight(user)
	local f = state.load(user, game.player(user))
	if f and f.outcome == "victory" then return f end
	return nil
end

-- A drop without its victory page (the fight's result gone): the card on a page of its own.
local function drop_page(req, drop, note)
	return show(req, "Item Drop", "fight/drop", { offer = drop_offer(req.user, drop), note = note })
end

-- GET /drop: the victory page shows the drop; the old address leads there.
local function drop_get(req)
	local drop = pending_drop(req.user)
	if not drop then return go(req, "/") end
	if won_fight(req.user) then return go(req, "/victory") end
	return drop_page(req, drop)
end

-- GET /drop/room: the bag, to discard something and take the drop (the drop card's "Make
-- room", a dialog: data-modal; a page of its own without JavaScript): every bag entry but
-- quest items, each a POST /drop with take and discard.
local function drop_room(req)
	local drop = pending_drop(req.user)
	if not drop then return go(req, "/") end
	local bag = {}
	for _, e in ipairs(inventory.bag(req.user.id)) do
		if e.item.category ~= "quest" then bag[#bag + 1] = { entry = e, icon = items.icon_url(e.item) } end
	end
	return show(req, "Make Room", "fight/drop_room", { drop = drop, bag = bag,
		room = inventory.room(drop, inventory.bag(req.user.id), inventory.size()) > 0 })
end

-- POST /drop: "equip" (a slot: wear it there, what was in it into the bag), "take" (into
-- the bag; with "discard", a bag entry thrown away first to make room) or "leave". What
-- happened goes onto the victory page (fights.result.drop_note), which the answer leads
-- back to; without it, the drop's own page says it.
local function drop_post(req)
	local user = req.user
	local drop = pending_drop(user)
	if not drop then return go(req, "/") end
	local f = won_fight(user)
	local function done(note)
		dk.db:exec("UPDATE users SET dropcode = 0 WHERE id = ?", user.id)
		if not f then return show(req, "Item Drop", "fight/drop_taken", { note = note }) end
		f.result.drop_note = note
		dk.db:exec("UPDATE fights SET result = ? WHERE user_id = ?", state.encode(f.result), user.id)
		return go(req, "/victory")
	end
	local function refused(msg)
		if f then
			f.result.drop_note = nil
			local title, ctx = encounter.victory_page(f.result)
			ctx.offer = drop_offer(user, drop)
			ctx.offer.error = msg
			return show(req, title, "fight/victory", ctx)
		end
		return drop_page(req, drop, msg)
	end
	local form = req.form
	if form.leave ~= nil then return done("You left the " .. drop.name .. " behind.") end
	if form.equip ~= nil then
		local o = drop_offer(user, drop)
		for _, c in ipairs(o.equips) do
			if c.slot == form.equip then
				if not c.ok then return refused("Your bag is full: there is no room for your " .. c.old.item.name .. ".") end
				inventory.equip_new(user.id, drop, c.slot)
				local note = "You equipped the " .. drop.name .. "."
				if c.old then note = note .. " Your " .. c.old.item.name .. " is in your bag." end
				return done(note)
			end
		end
		return refused("Choose where to equip the " .. drop.name .. ".")
	end
	if form.take == nil then return go(req, f and "/victory" or "/drop") end
	local discard_id = php.intval(form.discard)
	local discarded
	if discard_id ~= 0 then
		local e = inventory.entry(user.id, discard_id)
		if not e or e.equipped or e.item.category == "quest" then return refused("Choose an item from your bag to discard.") end
		inventory.take(e)
		discarded = e
	end
	if not inventory.add(user.id, drop, 1) then
		return refused("Your bag is full. Make room in it first, or leave the " .. drop.name .. ".")
	end
	return done((discarded and ("You discarded the " .. discarded.item.name .. ". ") or "") ..
		"The " .. drop.name .. " is in your bag.")
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
	r:get("/drop/room", auth.game, drop_room)
	r:post("/drop", auth.game, drop_post)
	r:get("/dead", auth.game, dead)
end
