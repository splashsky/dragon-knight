-- routes/fight.lua :: fighting, victory, item drops, death (port of legacy fight.php).
--   GET/POST /fight   fight() -- POST buttons: fight | spell (+ userspell) | item (+ useritem) | run
--   GET      /victory victory()
--   GET/POST /drop    drop()  -- POST: take (+ discard: a bag entry to make room) | leave
--   GET      /dead    dead()
-- The dice and formulas live in fight/combat.lua; this module loads and saves state.
local auth = require("lib.auth")
local classes = require("lib.classes")
local combat = require("fight.combat")
local game = require("lib.game")
local inventory = require("lib.inventory")
local items = require("lib.items")
local php = require("lib.php")
local spells = require("lib.spells")
local view = require("lib.view")

local rand = php.rand

local function error_page(req, html)
	return view.message(req, "Error", html)
end

local function monster_row(id)
	return dk.db:first("SELECT * FROM monsters WHERE id = ?", id)
end

local function pick_monster(user)
	local minlevel, maxlevel = combat.monster_levels(user.latitude, user.longitude)
	local rows = dk.db:query("SELECT * FROM monsters WHERE level >= ? AND level <= ? ORDER BY id",
													 minlevel, maxlevel)
	return combat.pick(rows, rand)
end

local function save_death(user, st)
	local d = combat.death(st)
	-- fixed: legacy kept the uber buffs and didn't write currentmp, refunding the MP of a
	-- spell cast on the fatal turn.
	dk.db:exec([[UPDATE users SET currenthp = ?, currentmp = ?, currentaction = 'In Town',
		currentmonster = 0, currentmonsterhp = 0, currentmonstersleep = 0, currentmonsterimmune = 0,
		currentuberdamage = 0, currentuberdefense = 0, currentfight = 0, latitude = 0,
		longitude = 0, gold = ? WHERE id = ?]], d.currenthp, st.currentmp, d.gold, user.id)
end

-- Monster's turn + death bookkeeping shared by every branch. Returns lines, died.
local function monster_turn(user, st, monster, after_spell)
	local lines, died = combat.monster_turn(st, monster, rand, after_spell)
	if died then save_death(user, st) end
	return lines, died
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

local function fight(req)
	local user = req.user
	if user.currentaction ~= "Fighting" then
		return error_page(req, "Cheat attempt detected.<br><br>Get a life, loser.")
	end
	local form = req.method == "POST" and req.form or {}
	local st = game.player(user)

	-- First, check to see if we need to pick a monster.
	local swing_first = true
	local monster
	if user.currentfight == 1 then
		monster = pick_monster(user)
		if not monster then
			return error_page(req, "There are no monsters in this area. Please contact the game administrator.")
		end
		swing_first = combat.start(st, monster, rand)
	else
		monster = monster_row(st.currentmonster)
		if not monster then
			-- the monster was deleted mid-fight: start over with a new one
			monster = pick_monster(user)
			if not monster then
				return error_page(req, "There are no monsters in this area. Please contact the game administrator.")
			end
			swing_first = combat.start(st, monster, rand)
		end
	end

	local page = { monstername = monster.name, yourturn = {}, monsterturn = {} }
	local died = false

	if form.run ~= nil then
		-- fixed: legacy always let the player escape (a failed run's damage was never saved,
		-- and a fatal blow left them 'Exploring' at 0,0) and kept the fight state.
		if combat.run_chance(st, monster, rand) then
			dk.db:exec([[UPDATE users SET currentaction = 'Exploring', currentfight = 0,
				currentmonster = 0, currentmonsterhp = 0, currentmonstersleep = 0,
				currentmonsterimmune = 0, currentuberdamage = 0, currentuberdefense = 0
				WHERE id = ?]], user.id)
			return view.redirect("/")
		end
		page.yourturn = { "You tried to run away, but were blocked in front!" }
		page.monsterhp = st.currentmonsterhp
		page.monsterturn, died = monster_turn(user, st, monster, false)

	elseif form.fight ~= nil then
		local killed
		page.yourturn, killed = combat.attack(st, monster, rand)
		page.monsterhp = st.currentmonsterhp
		if killed then
			-- fixed: legacy saved only currentmonsterhp; currentmonster is saved too so a
			-- first-turn kill (monster picked in this request) is credited to the right monster.
			dk.db:exec("UPDATE users SET currentmonsterhp = 0, currentmonster = ? WHERE id = ?",
								 st.currentmonster, user.id)
			return view.redirect("/victory")
		end
		page.monsterturn, died = monster_turn(user, st, monster, false)

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
		local refused = combat.cast_error(st, spell)
		if refused then return error_page(req, refused) end
		local killed
		page.yourturn, killed = combat.cast(st, spell, rand)
		page.monsterhp = st.currentmonsterhp
		if killed then
			dk.db:exec([[UPDATE users SET currentmonsterhp = 0, currenthp = ?, currentmp = ?,
				currentmonster = ? WHERE id = ?]], st.currenthp, st.currentmp, st.currentmonster, user.id)
			return view.redirect("/victory")
		end
		page.monsterturn, died = monster_turn(user, st, monster, true)

	elseif form.item ~= nil then
		-- a consumable from the bag: costs the turn like a spell (refusals cost nothing)
		local picked = form.useritem
		if picked == nil or php.intval(picked) == 0 then
			return error_page(req, "You must select an item first. Please go back and try again.")
		end
		-- validated server-side: an integer item id with a stack in the user's bag
		local item_id = math.tointeger(tonumber(picked))
		local entry = item_id and inventory.find(user.id, item_id)
		if not entry then
			return error_page(req, "You do not have this item. Please go back and try again.")
		end
		local refused = combat.use_error(st, entry.item)
		if refused then return error_page(req, refused) end
		inventory.take(entry, 1)
		local killed
		page.yourturn, killed = combat.use(st, entry.item, rand)
		page.monsterhp = st.currentmonsterhp
		if killed then
			dk.db:exec([[UPDATE users SET currentmonsterhp = 0, currenthp = ?, currentmp = ?, currenttp = ?,
				currentmonster = ? WHERE id = ?]], st.currenthp, st.currentmp, st.currenttp, st.currentmonster, user.id)
			return view.redirect("/victory")
		end
		page.monsterturn, died = monster_turn(user, st, monster, true)

	elseif not swing_first then
		-- Do a monster's turn if person lost the chance to swing first.
		page.yourturn = { "The monster attacks before you are ready!" }
		page.monsterhp = st.currentmonsterhp
		page.monsterturn, died = monster_turn(user, st, monster, false)

	else
		page.monsterhp = st.currentmonsterhp
	end

	if died then
		page.dead = true
	else
		page.spells = spells.known(user, "fight")
		page.items = usable_items(user)
		dk.db:exec([[UPDATE users SET currentaction = 'Fighting', currenthp = ?, currentmp = ?,
			currenttp = ?, currentfight = ?, currentmonster = ?, currentmonsterhp = ?, currentmonstersleep = ?,
			currentmonsterimmune = ?, currentuberdamage = ?, currentuberdefense = ? WHERE id = ?]],
			st.currenthp, st.currentmp, st.currenttp, math.min(st.currentfight + 1, combat.MAX_FIGHT),
			st.currentmonster, st.currentmonsterhp, st.currentmonstersleep, st.currentmonsterimmune,
			st.currentuberdamage, st.currentuberdefense, user.id)
	end
	return view.page(req, "Fighting", "fight/fight", page)
end

local function victory(req)
	local user = req.user
	if user.currentmonsterhp ~= 0 then return view.redirect("/fight") end
	if user.currentfight == 0 then return view.redirect("/") end
	local monster = monster_row(user.currentmonster)
	-- fixed: legacy paid out for a missing monster (e.g. /victory right after an encounter
	-- began, before the monster was picked: currentmonster 0, currentmonsterhp 0).
	if not monster then return view.redirect("/") end

	local r = combat.rewards(game.player(user), monster, rand)
	local ctx = { monster = monster, r = r }
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
																"AND droppable <> 0 AND retired = 0 ORDER BY id", monster.level)
			local drop = combat.pick(drops, rand)
			-- fixed: legacy showed the drop text even with no eligible drop (dropcode stored as 0).
			dropcode = drop and drop.id or 0
			ctx.dropped = drop ~= nil
		end
		title = "Victory!"
	end

	-- level-ups grow the base stats (lib/stats.lua). experience/gold were MEDIUMINT
	-- UNSIGNED: a bonus below -100% made them negative and MySQL stored 0.
	dk.db:exec([[UPDATE users SET currentaction = 'Exploring', level = ?, base_maxhp = base_maxhp + ?,
		base_maxmp = base_maxmp + ?, base_maxtp = base_maxtp + ?, strength = strength + ?,
		dexterity = dexterity + ?, currentfight = 0, currentmonster = 0, currentmonsterhp = 0,
		currentmonstersleep = 0, currentmonsterimmune = 0, currentuberdamage = 0, currentuberdefense = 0,
		dropcode = ?, experience = ?, gold = ? WHERE id = ?]],
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
