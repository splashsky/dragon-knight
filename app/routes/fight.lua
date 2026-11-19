-- routes/fight.lua :: fighting, victory, item drops, death (port of legacy fight.php).
--   GET/POST /fight   fight() -- POST buttons: fight | spell (+ userspell) | item (+ useritem) | run
--                     | continue (a turn a status blocks)
--   GET      /victory victory()
--   GET/POST /drop    drop()  -- POST: take (+ discard: a bag entry to make room) | leave
--   GET      /dead    dead()
-- The fight is a model loaded and saved once per request (fight/state.lua); a request
-- plays at most one round of the pipeline (fight/round.lua), whose dice and formulas live
-- in fight/combat.lua. This module picks the monster, checks the player's choice, and
-- saves.
local auth = require("lib.auth")
local classes = require("lib.classes")
local combat = require("fight.combat")
local game = require("lib.game")
local inventory = require("lib.inventory")
local items = require("lib.items")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")
local view = require("lib.view")

local rand = php.rand

local function error_page(req, html)
	return view.message(req, "Error", html)
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

-- The fight's "Use item" list: consumables in the bag usable in fights, one line per item
-- with the quantity over all its stacks.
local function usable_items(user)
	local out, by_id = {}, {}
	for _, e in ipairs(inventory.bag(user.id)) do
		if items.usable(e.item, "fight") then
			local line = by_id[e.item.id]
			if not line then
				line = { id = e.item.id, name = e.item.name, qty = 0 }
				by_id[e.item.id] = line
				out[#out + 1] = line
			end
			line.qty = line.qty + e.qty
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

-- What the fight page shows of the fight: the enemies of the wave, the allies, statuses.
local function view_of(f)
	local p = state.player(f)
	local enemies, allies = {}, {}
	for _, c in ipairs(state.side(f, "enemy", true)) do
		-- MP only for monsters with spells (what it means to the player)
		local casts = #monsters.loadout(c.row).spells > 0
		enemies[#enemies + 1] = { name = c.row.name, hp = c.hp, mp = casts and c.mp or nil, statuses = status_list(c) }
	end
	for _, c in ipairs(state.allies(f)) do
		allies[#allies + 1] = { name = c.row.name, hp = c.hp, maxhp = c.maxhp, turns = c.turns_left,
			statuses = status_list(c) }
	end
	return { enemies = enemies, allies = allies, player_statuses = status_list(p) }
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
	if user.currentaction ~= "Fighting" then
		return error_page(req, "Cheat attempt detected.<br><br>Get a life, loser.")
	end
	local form = req.method == "POST" and req.form or {}
	local st = game.player(user)

	-- First, check to see if we need to pick a monster (an encounter just began, or its
	-- monster was deleted mid-fight: start over with a new one).
	local f = state.load(user, st)
	local swing_first = true
	if not f or f.round <= 1 or #state.side(f, "enemy", true) == 0 then
		local monster = pick_monster(user)
		if not monster then
			return error_page(req, "There are no monsters in this area. Please contact the game administrator.")
		end
		f, swing_first = encounter(user, st, f and f.round or 1, monster)
	elseif state.won(f) then
		-- fixed: legacy showed a defeated monster (0 HP) until /victory was visited.
		return view.redirect("/victory")
	end
	f.rand = rand
	f.max_allies = game.control().max_allies or 1

	-- The player's choice: a status that blocks the action (asleep, recharging, ...) leaves
	-- only "Continue".
	local locked = round.locked(f)
	local a, entry
	if locked and (form.run or form.fight or form.spell or form.item or form.continue) ~= nil then
		a = { kind = "continue" }
	elseif form.run ~= nil then
		a = { kind = "run" }
	elseif form.fight ~= nil then
		a = { kind = "attack" }
	elseif form.spell ~= nil then
		local picked = form.userspell
		if picked == nil or php.intval(picked) == 0 then
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
	elseif form.item ~= nil then
		-- a consumable from the bag: costs the turn like a spell (refusals cost nothing)
		local picked = form.useritem
		if picked == nil or php.intval(picked) == 0 then
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

	local page = { yourturn = {}, allyturn = {}, monsterturn = {}, roundend = {} }
	if a then
		local r = round.play(f, a)
		-- refusal texts may come from content files and admin overrides: escaped
		if r.refused then return error_page(req, dk.html(r.refused)) end
		if entry then inventory.take(entry, 1) end
		f = r.f
		page.yourturn, page.allyturn, page.monsterturn, page.roundend = r.player, r.allies, r.enemies, r.ending
		if r.escaped then
			-- fixed: legacy always let the player escape (a failed run's damage was never saved,
			-- and a fatal blow left them 'Exploring' at 0,0) and kept the fight state.
			state.clear(user.id)
			save_player(user, f.st)
			dk.db:exec("UPDATE users SET currentaction = 'Exploring' WHERE id = ?", user.id)
			return view.redirect("/")
		elseif r.victory then
			-- the round's counter stays: /victory pays out and ends the fight
			state.save(f)
			save_player(user, f.st)
			return view.redirect("/victory")
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
	if not page.dead then
		page.locked = round.locked(f)
		page.spells = spells.known(user, "fight")
		page.items = usable_items(user)
		f.round = math.min(f.round + 1, state.MAX_ROUND)
		state.save(f)
		dk.db:exec("UPDATE users SET currentaction = 'Fighting', currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
			f.st.currenthp, f.st.currentmp, f.st.currenttp, user.id)
	end
	return view.page(req, "Fighting", "fight/fight", page)
end

local function victory(req)
	local user = req.user
	local player = game.player(user)
	local f = state.load(user, player)
	-- fixed: legacy paid out for a missing monster (e.g. /victory right after an encounter
	-- began, before the monster was picked).
	if not f or #state.side(f, "enemy", true) == 0 then return view.redirect("/") end
	if not state.won(f) then return view.redirect("/fight") end

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
	return view.page(req, title, "fight/victory", ctx)
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
	return view.page(req, "Item Drop", "fight/drop", ctx)
end

local function drop_get(req)
	local drop = pending_drop(req.user)
	if not drop then return view.redirect("/") end
	return drop_page(req, drop)
end

-- POST /drop: "take" puts the item into the bag (after discarding bag entry `discard`
-- when the bag is full); "leave" gives it up.
local function drop_post(req)
	local user = req.user
	local drop = pending_drop(user)
	if not drop then return view.redirect("/") end
	if req.form.leave ~= nil then
		dk.db:exec("UPDATE users SET dropcode = 0 WHERE id = ?", user.id)
		return view.redirect("/")
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
	return view.page(req, "Item Drop", "fight/drop_taken", { drop = drop, discarded = discarded })
end

-- legacy dead() built this page but never displayed it; deaths are reported on the
-- fight page. Kept as a read-only page.
local function dead(req)
	return view.page(req, "You Have Died", "fight/dead", {})
end

return function(r)
	r:get("/fight", auth.game, fight)
	r:post("/fight", auth.game, fight)
	r:get("/victory", auth.game, victory)
	r:get("/drop", auth.game, drop_get)
	r:post("/drop", auth.game, drop_post)
	r:get("/dead", auth.game, dead)
end
