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
-- The fight is a model loaded and saved once per request (fight/state.lua); a request
-- plays at most one round of the pipeline (fight/round.lua), whose dice and formulas live
-- in fight/combat.lua. This module picks the monster, checks the player's choice, and
-- saves.
--
-- The JSON fight API (docs/APP.md "Fight API"; public/js/fight.js): the same routes, asked
-- with Accept: application/json, run the same code and answer { events, fragments, round,
-- redirect, url, title, stale } instead of the page (a redirect is a field, not a 302:
-- fetch would follow it and lose the round's events), or { error } instead of an error
-- page. Every fight form carries the round it was shown at: a POST /fight with another
-- round (a second click, an older tab) plays nothing and shows the fight as it is now.
local act = require("fight.act")
local auth = require("lib.auth")
local classes = require("lib.classes")
local combat = require("fight.combat")
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

-- The fight pages load fight.js.
local PAGE = { scripts = { "fight" } }

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
	return view.page(req, title, template, ctx, PAGE)
end

-- A redirect, or { redirect = url } with the fields of t.
local function go(req, url, t)
	if not view.wants_json(req) then return view.redirect(url) end
	t = t or {}
	t.redirect = url
	t.events = t.events or json.array()
	return view.json(t)
end

-- The original random pick among the roaming monsters of the level band (retired ones and
-- those that don't roam are never met at random).
local function pick_monster(user)
	local minlevel, maxlevel = combat.monster_levels(user.latitude, user.longitude)
	return combat.pick(monsters.roaming(minlevel, maxlevel), rand)
end

local function save_player(user, st)
	dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
						 st.currenthp, st.currentmp, st.currenttp, user.id)
end

local function save_death(user, st)
	local d = combat.death(st)
	-- fixed: legacy kept the uber buffs and didn't write currentmp, refunding the MP of a
	-- spell cast on the fatal turn. The fight (and its statuses) ends.
	state.clear(user.id)
	dk.db:exec([[UPDATE users SET currenthp = ?, currentmp = ?, currentaction = 'In Town', latitude = 0,
		longitude = 0, gold = ? WHERE id = ?]], d.currenthp, st.currentmp, d.gold, user.id)
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

-- A new encounter against `monster` (the fight's counter is kept). Returns the model and
-- whether the player swings first.
local function encounter(user, st, fight_round, monster)
	local f = state.new({ user_id = user.id, round = fight_round, st = st })
	state.add_monster(f, monster, 1)
	f.rand = rand
	return f, round.start(f)
end

local function fight(req)
	local user = req.user
	local form = req.method == "POST" and req.form or {}
	-- the round the form was shown at (absent: a form from before 2.3, or a GET)
	local sent = form.round ~= nil and php.intval(form.round) or nil
	if user.currentaction ~= "Fighting" then
		-- a form of a fight that is over: the game as it is now
		if sent then return go(req, "/", { stale = true }) end
		return error_page(req, "Cheat attempt detected. Get a life, loser.", "Cheat attempt detected.<br><br>Get a life, loser.")
	end
	local st = game.player(user)

	-- A form shown at another round than the fight's (a second click, an older tab) plays
	-- nothing: the fight page as a GET would show it, with a note.
	local f = state.load(user, st)
	local stale = sent ~= nil and (not f or sent ~= f.round)
	if stale then form = {} end

	-- First, check to see if we need to pick a monster (an encounter just began, or its
	-- monster was deleted mid-fight: start over with a new one).
	local swing_first = true
	if not f or f.round <= 1 or #state.side(f, "enemy", true) == 0 then
		local monster = pick_monster(user)
		if not monster then
			return error_page(req, "There are no monsters in this area. Please contact the game administrator.")
		end
		f, swing_first = encounter(user, st, f and f.round or 1, monster)
	elseif state.won(f) then
		-- fixed: legacy showed a defeated monster (0 HP) until /victory was visited.
		return go(req, "/victory", { stale = stale or nil })
	end
	f.rand = rand
	f.max_allies = game.control().max_allies or 1

	-- The player's choice: a status that blocks the action (asleep, recharging, ...) leaves
	-- only "Continue".
	local locked = round.locked(f)
	local a, entry, gear
	if locked and (form.run or form.fight or form.spell or form.item or form.use_gear or form.continue) ~= nil then
		a = { kind = "continue" }
	elseif form.run ~= nil then
		a = { kind = "run" }
	elseif form.fight ~= nil then
		a = { kind = "attack" }
	elseif form.spell ~= nil then
		-- the icon button's value, or the old select's (spell=Spell&userspell=<id>)
		local picked = form.userspell
		if picked == nil then picked = form.spell end
		if php.intval(picked) == 0 then
			return error_page(req, "You must select a spell first. Please go back and try again.")
		end
		-- Validated server-side: an integer id the user knows that exists in spells.
		local spell_id = math.tointeger(tonumber(picked))
		local spell = spell_id and spells.knows(user, spell_id) and spells.get(spell_id) or nil
		if not spell then
			return error_page(req, "You have not yet learned this spell. Please go back and try again.")
		end
		if st.currentmp < spell.mp then
			return error_page(req, "You do not have enough Magic Points to cast this spell. Please go back and try again.")
		end
		a = { kind = "spell", spell = spell }
	elseif form.use_gear ~= nil then
		-- an equipped item that casts a spell: a charge instead of MP, the turn like an item
		local entry_id = math.tointeger(tonumber(form.use_gear))
		gear = entry_id and inventory.entry(user.id, entry_id)
		if not gear or not gear.equipped or not items.casts(gear.item) then
			return error_page(req, "You do not have this item equipped. Please go back and try again.")
		end
		local spell = items.spell(gear.item)
		if not spell then return error_page(req, act.CANNOT.item) end
		if gear.charges < 1 then
			return error_page(req, "The " .. gear.item.name .. " has no charges left. Rest at an inn to recharge it.")
		end
		a = { kind = "gear", item = gear.item, spell = spell }
	elseif form.item ~= nil then
		-- a consumable from the bag: costs the turn like a spell (refusals cost nothing); the
		-- icon button's value, or the old select's (item=Use Item&useritem=<id>)
		local picked = form.useritem
		if picked == nil then picked = form.item end
		if php.intval(picked) == 0 then
			return error_page(req, "You must select an item first. Please go back and try again.")
		end
		-- validated server-side: an integer item id with a stack in the user's bag
		local item_id = math.tointeger(tonumber(picked))
		entry = item_id and inventory.find(user.id, item_id)
		if not entry then
			return error_page(req, "You do not have this item. Please go back and try again.")
		end
		a = { kind = "item", item = entry.item }
	elseif form.continue == nil and not swing_first then
		-- the monster swung first
		a = { kind = "ambush" }
	end

	local page = { yourturn = {}, allyturn = {}, monsterturn = {}, roundend = {}, stale = stale }
	local evs = json.array()
	if a then
		if view.wants_json(req) then f.trace = {} end
		local r = round.play(f, a)
		-- refusal texts may come from content files and admin overrides: escaped
		if r.refused then return error_page(req, r.refused) end
		if entry then inventory.take(entry, 1) end
		if gear then inventory.spend_charge(gear) end
		f = r.f
		if f.trace then evs = round_events(r) end
		page.yourturn, page.allyturn, page.monsterturn, page.roundend = r.player, r.allies, r.enemies, r.ending
		if r.escaped then
			-- fixed: legacy always let the player escape (a failed run's damage was never saved,
			-- and a fatal blow left them 'Exploring' at 0,0) and kept the fight state.
			state.clear(user.id)
			save_player(user, f.st)
			dk.db:exec("UPDATE users SET currentaction = 'Exploring' WHERE id = ?", user.id)
			return go(req, "/", { events = evs })
		elseif r.victory then
			-- the round's counter stays: /victory pays out and ends the fight
			state.save(f)
			save_player(user, f.st)
			return go(req, "/victory", { events = evs })
		elseif r.died then
			save_death(user, f.st)
			page.dead = true
		end
	end

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
		f.round = f.round + 1
		page.round = f.round
		state.save(f)
		dk.db:exec("UPDATE users SET currentaction = 'Fighting', currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
			f.st.currenthp, f.st.currentmp, f.st.currenttp, user.id)
	end
	return show(req, "Fighting", "fight/fight", page, { events = evs, round = page.round, stale = stale or nil })
end

local function victory(req)
	local user = req.user
	local player = game.player(user)
	local f = state.load(user, player)
	-- fixed: legacy paid out for a missing monster (e.g. /victory right after an encounter
	-- began, before the monster was picked).
	if not f or #state.side(f, "enemy", true) == 0 then return go(req, "/") end
	if not state.won(f) then return go(req, "/fight") end

	-- rewards per defeated enemy (summed), the drop roll once per encounter
	local r = { exp = 0, gold = 0, warnexp = "", warngold = "" }
	local names, top = {}, nil
	for _, c in ipairs(f.combatants) do
		if c.side == "enemy" then
			local one = combat.rewards(player, c.row, rand)
			player.experience, player.gold = one.newexp, one.newgold
			r.exp, r.gold = r.exp + one.exp, r.gold + one.gold
			r.newexp, r.newgold = one.newexp, one.newgold
			if one.warnexp ~= "" then r.warnexp = one.warnexp end
			if one.warngold ~= "" then r.warngold = one.warngold end
			names[#names + 1] = c.row.name
			if not top or c.row.level > top.level then top = c.row end
		end
	end
	local ctx = { monster = top, defeated = table.concat(names, ", the "), r = r }
	-- a character of an unknown class gains experience but no levels
	local cls = classes.get(user.charclass)
	local up
	if cls then
		local levels = classes.levels(cls)
		up = combat.level_up(user, cls, r.newexp, function(level) return levels[level] end)
	end
	local title
	local g = { level = user.level, hp = 0, mp = 0, tp = 0, strength = 0, dexterity = 0 }
	local dropcode = user.dropcode
	if up then
		g = up
		for _, learned in ipairs(up.spells or {}) do spells.learn(user.id, learned.id, learned.level) end
		ctx.levelup = up
		title = "Courage and Wit have served thee well!"
	else
		if combat.drop_roll(rand) then
			-- the original drops are items 34-65, in the same order: same odds, same picks
			local drops = dk.db:query("SELECT id FROM items WHERE drop_level IS NOT NULL AND drop_level <= ? " ..
																"AND droppable <> 0 AND retired = 0 ORDER BY id", top.level)
			local drop = combat.pick(drops, rand)
			-- fixed: legacy showed the drop text even with no eligible drop (dropcode stored as 0).
			dropcode = drop and drop.id or 0
			ctx.dropped = drop ~= nil
		end
		title = "Victory!"
	end

	-- level-ups grow the base stats (lib/stats.lua). experience/gold were MEDIUMINT
	-- UNSIGNED: a bonus below -100% made them negative and MySQL stored 0. The fight (and
	-- every status of it) ends.
	state.clear(user.id)
	dk.db:exec([[UPDATE users SET currentaction = 'Exploring', level = ?, base_maxhp = base_maxhp + ?,
		base_maxmp = base_maxmp + ?, base_maxtp = base_maxtp + ?, strength = strength + ?,
		dexterity = dexterity + ?, dropcode = ?, experience = ?, gold = ? WHERE id = ?]],
		g.level, g.hp, g.mp, g.tp, g.strength, g.dexterity, dropcode, php.mysql_uint(r.newexp),
		php.mysql_uint(r.newgold), user.id)
	return show(req, title, "fight/victory", ctx)
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
