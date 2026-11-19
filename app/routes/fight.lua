-- routes/fight.lua :: fighting, victory, item drops, death (port of legacy fight.php).
--   GET/POST /fight   fight() -- POST buttons: fight | spell (+ userspell) | run
--   GET      /victory victory()
--   GET/POST /drop    drop()  -- POST: slot (1-3)
--   GET      /dead    dead()
-- The dice and formulas live in fight/combat.lua; this module loads and saves state.
local auth = require("lib.auth")
local combat = require("fight.combat")
local game = require("lib.game")
local php = require("lib.php")
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

local function fight(req)
	local user = req.user
	if user.currentaction ~= "Fighting" then
		return error_page(req, "Cheat attempt detected.<br><br>Get a life, loser.")
	end
	local form = req.method == "POST" and req.form or {}
	local st = {}
	for k, v in pairs(user) do st[k] = v end

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
		local spell = spell_id and php.in_list(user.spells, spell_id) and
									dk.db:first("SELECT * FROM spells WHERE id = ?", spell_id) or nil
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
		page.spells = game.user_spells(user)
		dk.db:exec([[UPDATE users SET currentaction = 'Fighting', currenthp = ?, currentmp = ?,
			currentfight = ?, currentmonster = ?, currentmonsterhp = ?, currentmonstersleep = ?,
			currentmonsterimmune = ?, currentuberdamage = ?, currentuberdefense = ? WHERE id = ?]],
			st.currenthp, st.currentmp, math.min(st.currentfight + 1, combat.MAX_FIGHT),
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

	local r = combat.rewards(user, monster, rand)
	local ctx = { monster = monster, r = r }
	local key = function(stat) return game.level_key(user.charclass, stat) end
	local up = combat.level_up(user, r.newexp, key, game.level_row)
	local title
	local s = {
		level = user.level, maxhp = user.maxhp, maxmp = user.maxmp, maxtp = user.maxtp,
		strength = user.strength, dexterity = user.dexterity, attackpower = user.attackpower,
		defensepower = user.defensepower, spells = user.spells, dropcode = user.dropcode,
	}
	if up then
		s.level, s.maxhp, s.maxmp, s.maxtp = up.level, up.maxhp, up.maxmp, up.maxtp
		s.strength, s.dexterity = up.newstrength, up.newdexterity
		s.attackpower, s.defensepower = up.attackpower, up.defensepower
		if up.spells then s.spells = up.spells end
		ctx.levelup = up
		title = "Courage and Wit have served thee well!"
	else
		if combat.drop_roll(rand) then
			local drops = dk.db:query("SELECT id FROM drops WHERE mlevel <= ? ORDER BY id", monster.level)
			local drop = combat.pick(drops, rand)
			-- fixed: legacy showed the drop text even with no eligible drop (dropcode stored as 0).
			s.dropcode = drop and drop.id or 0
			ctx.dropped = drop ~= nil
		end
		title = "Victory!"
	end

	-- experience/gold were MEDIUMINT UNSIGNED: a bonus below -100% made them negative and
	-- MySQL stored 0.
	dk.db:exec([[UPDATE users SET currentaction = 'Exploring', level = ?, maxhp = ?, maxmp = ?,
		maxtp = ?, strength = ?, dexterity = ?, attackpower = ?, defensepower = ?, spells = ?,
		currentfight = 0, currentmonster = 0, currentmonsterhp = 0, currentmonstersleep = 0,
		currentmonsterimmune = 0, currentuberdamage = 0, currentuberdefense = 0, dropcode = ?,
		experience = ?, gold = ? WHERE id = ?]],
		s.level, s.maxhp, s.maxmp, s.maxtp, s.strength, s.dexterity, s.attackpower,
		s.defensepower, s.spells, s.dropcode, php.mysql_uint(r.newexp), php.mysql_uint(r.newgold),
		user.id)
	return view.page(req, title, "fight/victory", ctx)
end

local function drop_row(id)
	return dk.db:first("SELECT * FROM drops WHERE id = ?", id)
end

-- Inventory slot columns, whitelisted (legacy put $_POST["slot"] into the SQL).
local SLOTS = {
	["1"] = { id = "slot1id", name = "slot1name" },
	["2"] = { id = "slot2id", name = "slot2name" },
	["3"] = { id = "slot3id", name = "slot3name" },
}

local function drop_get(req)
	local user = req.user
	if user.dropcode == 0 then return view.redirect("/") end
	local drop = drop_row(user.dropcode)
	if not drop then return view.redirect("/") end
	return view.page(req, "Item Drop", "fight/drop", {
		drop = drop, attributes = combat.drop_attributes(drop),
		slots = { user.slot1name, user.slot2name, user.slot3name },
	})
end

local function drop_post(req)
	local user = req.user
	if user.dropcode == 0 then return view.redirect("/") end
	local drop = drop_row(user.dropcode)
	if not drop then return view.redirect("/") end
	local slot = SLOTS[tostring(req.form.slot or "")]
	if not slot then
		return error_page(req, "Please go back and select an inventory slot to continue.")
	end

	local st = {}
	for k, v in pairs(user) do st[k] = v end
	local old = user[slot.id] ~= 0 and drop_row(user[slot.id]) or nil
	combat.equip_drop(st, drop, old)

	-- MySQL clamped negative values in the UNSIGNED columns to 0.
	local function col(name)
		if combat.SIGNED_STATS[name] then return php.mysql_int(st[name]) end
		return php.mysql_uint(st[name])
	end
	dk.db:exec("UPDATE users SET " .. slot.name .. " = ?, " .. slot.id .. [[ = ?,
		maxhp = ?, maxmp = ?, maxtp = ?, strength = ?, dexterity = ?, attackpower = ?,
		defensepower = ?, expbonus = ?, goldbonus = ?, currenthp = ?, currentmp = ?,
		currenttp = ?, dropcode = 0 WHERE id = ?]],
		drop.name, drop.id, col("maxhp"), col("maxmp"), col("maxtp"), col("strength"),
		col("dexterity"), col("attackpower"), col("defensepower"), col("expbonus"),
		col("goldbonus"), col("currenthp"), col("currentmp"), col("currenttp"), user.id)
	return view.message(req, "Item Drop",
		'The item has been equipped. You can now continue <a href="/">exploring</a>.')
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
