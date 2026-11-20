-- fight/encounter.lua :: how a fight begins and ends, for the POSTs that cause it (GETs
-- never change the game: docs/APP.md "Pure GETs"). An encounter begins on a map move (POST
-- /move): the monster is picked and, when it is quicker, its first strike is played right
-- there. It ends in a POST /fight round: a victory is paid out at once, a death costs what
-- it always did. A finished fight is kept (fights.outcome, its last round's lines in
-- fights.log, the rewards in fights.result) so GET /fight and GET /victory can show it
-- again, until the next encounter begins or the player moves or travels on.
local classes = require("lib.classes")
local combat = require("fight.combat")
local game = require("lib.game")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")

local encounter = {}

local rand = php.rand

-- The parts of the fight page a round's lines go in, in the page's order (the round's r
-- fields: player, allies, enemies, ending).
encounter.PARTS = { { "yourturn", "player" }, { "allyturn", "allies" }, { "monsterturn", "enemies" },
	{ "roundend", "ending" } }

-- A round's lines (r from round.play) as fights.log text: "<part>\t<line>" per line.
function encounter.log_of(r)
	local out = {}
	for _, p in ipairs(encounter.PARTS) do
		for _, line in ipairs(r[p[2]] or {}) do
			out[#out + 1] = p[1] .. "\t" .. tostring(line):gsub("[\t\n]", " ")
		end
	end
	return table.concat(out, "\n")
end

-- fights.log text -> { yourturn = { line, ... }, allyturn = ..., monsterturn = ..., roundend =
-- ..., note = text or nil, stale = true or nil }
function encounter.lines(log)
	local out = {}
	for _, p in ipairs(encounter.PARTS) do out[p[1]] = {} end
	for part, line in tostring(log or ""):gmatch("([^\t\n]+)\t([^\n]*)") do
		if out[part] then table.insert(out[part], line)
		elseif part == "note" then out.note = line
		elseif part == "stale" then out.stale = true end
	end
	return out
end

-- What the fight page says about the last command when it played nothing, kept with the
-- last round's lines (whose page it is shown on) until the next round replaces them:
-- kind "note" (a refusal: text) or "stale" (a form from an older page). Returns the new
-- fights.log text.
function encounter.with_note(log, kind, text)
	local keep = {}
	for line in tostring(log or ""):gmatch("[^\n]+") do
		local part = line:match("^([^\t]*)\t")
		if part ~= "note" and part ~= "stale" then keep[#keep + 1] = line end
	end
	keep[#keep + 1] = kind .. "\t" .. tostring(text or ""):gsub("[\t\n]", " ")
	return table.concat(keep, "\n")
end

-- The original random pick among the roaming monsters of the level band at (lat, lon)
-- (retired ones and those that don't roam are never met at random).
function encounter.pick(lat, lon)
	local minlevel, maxlevel = combat.monster_levels(lat, lon)
	return combat.pick(monsters.roaming(minlevel, maxlevel), rand)
end

-- The player's numbers after a round (users' HP/MP/TP; the fight's tables are state.save's).
function encounter.save_player(user_id, st)
	dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
		st.currenthp, st.currentmp, st.currenttp, user_id)
end

-- The player died in the round r: half the gold, a quarter of the HP, back to town. The
-- fight is kept as it ended (outcome "death") for its page.
function encounter.die(user, r)
	local f, st = r.f, r.f.st
	local d = combat.death(st)
	-- fixed: legacy kept the uber buffs and didn't write currentmp, refunding the MP of a
	-- spell cast on the fatal turn. The fight (and its statuses) ends.
	f.outcome, f.log = "death", encounter.log_of(r)
	state.save(f)
	dk.db:exec([[UPDATE users SET currenthp = ?, currentmp = ?, currentaction = 'In Town', latitude = 0,
		longitude = 0, gold = ? WHERE id = ?]], d.currenthp, st.currentmp, d.gold, user.id)
end

-- The player won fight f (r: the round that won it, nil for a fight won before 3.0): the
-- rewards per defeated enemy (summed), a level-up or the drop roll (once per encounter),
-- paid now; the fight is kept with outcome "victory" and what GET /victory shows in
-- fights.result. `user`: the users row (as before the round: its experience and gold).
function encounter.win(user, f, r)
	local player = game.player(user)
	local res = { exp = 0, gold = 0, warnexp = "", warngold = "" }
	local names, top = {}, nil
	local newexp, newgold
	for _, c in ipairs(f.combatants) do
		if c.side == "enemy" then
			local one = combat.rewards(player, c.row, rand)
			player.experience, player.gold = one.newexp, one.newgold
			res.exp, res.gold = res.exp + one.exp, res.gold + one.gold
			newexp, newgold = one.newexp, one.newgold
			if one.warnexp ~= "" then res.warnexp = one.warnexp end
			if one.warngold ~= "" then res.warngold = one.warngold end
			names[#names + 1] = c.row.name
			if not top or c.row.level > top.level then top = c.row end
		end
	end
	res.defeated = table.concat(names, ", the ")
	-- a character of an unknown class gains experience but no levels
	local cls = classes.get(user.charclass)
	local up
	if cls then
		local levels = classes.levels(cls)
		up = combat.level_up(user, cls, newexp, function(level) return levels[level] end)
	end
	local g = { level = user.level, hp = 0, mp = 0, tp = 0, strength = 0, dexterity = 0 }
	local dropcode = user.dropcode
	if up then
		g = up
		for _, learned in ipairs(up.spells or {}) do spells.learn(user.id, learned.id, learned.level) end
		res.levelup, res.levels, res.learned = true, up.levels, up.learned
		res.hp, res.mp, res.tp, res.strength, res.dexterity = up.hp, up.mp, up.tp, up.strength, up.dexterity
	elseif combat.drop_roll(rand) then
		-- the original drops are items 34-65, in the same order: same odds, same picks
		local drops = dk.db:query("SELECT id FROM items WHERE drop_level IS NOT NULL AND drop_level <= ? " ..
			"AND droppable <> 0 AND retired = 0 ORDER BY id", top.level)
		local drop = combat.pick(drops, rand)
		-- fixed: legacy showed the drop text even with no eligible drop (dropcode stored as 0).
		dropcode = drop and drop.id or 0
		res.dropped = drop ~= nil
	end

	-- level-ups grow the base stats (lib/stats.lua). experience/gold were MEDIUMINT
	-- UNSIGNED: a bonus below -100% made them negative and MySQL stored 0.
	f.outcome, f.result = "victory", res
	if r then f.log = encounter.log_of(r) end
	state.save(f)
	dk.db:exec([[UPDATE users SET currentaction = 'Exploring', level = ?, base_maxhp = base_maxhp + ?,
		base_maxmp = base_maxmp + ?, base_maxtp = base_maxtp + ?, strength = strength + ?,
		dexterity = dexterity + ?, dropcode = ?, experience = ?, gold = ? WHERE id = ?]],
		g.level, g.hp, g.mp, g.tp, g.strength, g.dexterity, dropcode, php.mysql_uint(newexp),
		php.mysql_uint(newgold), user.id)
end

-- The victory page's title and ctx (templates/fight/victory.html) from fights.result.
function encounter.victory_page(res)
	local ctx = { defeated = res.defeated or "", r = {
		exp = res.exp or 0, gold = res.gold or 0, warnexp = res.warnexp or "", warngold = res.warngold or "" } }
	if res.levelup then
		ctx.levelup = { levels = res.levels, hp = res.hp, mp = res.mp, tp = res.tp, strength = res.strength,
			dexterity = res.dexterity, learned = res.learned }
		return "Courage and Wit have served thee well!", ctx
	end
	ctx.dropped = res.dropped
	return "Victory!", ctx
end

-- An encounter begins for player `user_id`, marked Fighting by the caller (the row is read
-- again: the caller saved the position, and a move's world statuses may have changed the
-- HP): any older fight goes, a monster of the level band where they stand is picked (each
-- enemy's HP rolled), and when it is quicker its first strike is played (an ambush). Saved.
-- Returns "fight" (go on fighting), "death" (the ambush killed the player: see
-- encounter.die) or nil when no monster can be met there (nothing changed).
function encounter.begin(user_id)
	local user = game.user(user_id)
	local monster = encounter.pick(user.latitude, user.longitude)
	if not monster then
		dk.log("warn", string.format("no roaming monsters for an encounter at %d, %d", user.latitude, user.longitude))
		return nil
	end
	state.clear(user.id)
	local st = game.player(user)
	local f = state.new({ user_id = user.id, round = 1, st = st })
	state.add_monster(f, monster, 1)
	f.rand = rand
	f.max_allies = game.control().max_allies or 1
	if not round.start(f) then
		local r = round.play(f, { kind = "ambush" })
		if r.died then
			encounter.die(user, r)
			return "death"
		end
		f = r.f
		f.log = encounter.log_of(r)
	end
	f.round = f.round + 1
	state.save(f)
	encounter.save_player(user.id, f.st)
	return "fight"
end

return encounter
