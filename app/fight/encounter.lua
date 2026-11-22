-- fight/encounter.lua :: how a fight begins, goes on with the clock and ends, for the POSTs
-- and the server's tick that cause it (GETs never change the game: docs/APP.md "Pure
-- GETs"). An encounter begins on a map move (POST /move): the monster is picked and, when
-- it is quicker, its first strike is played right there. The clock advances it (the
-- server's tick, and every POST /fight before its command: encounter.advance). It ends in
-- a round (a command's, or a guard when the turn ran out) or a clock tick: a victory is
-- paid out at once, a death costs what it always did. A finished fight is kept
-- (fights.outcome, its last lines in fights.log, the rewards in fights.result) so GET
-- /fight and GET /victory can show it again, until the next encounter begins or the
-- player moves or travels on.
local classes = require("lib.classes")
local clock = require("lib.clock")
local combat = require("fight.combat")
local fields = require("fight.fields")
local game = require("lib.game")
local hotbar = require("lib.hotbar")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local speech = require("fight.speech")
local spells = require("lib.spells")
local state = require("fight.state")

local encounter = {}

local rand = php.rand

-- The page's paragraphs for the parts of a round's lines (round.PARTS).
encounter.PARTS = { player = "yourturn", allies = "allyturn", enemies = "monsterturn", ending = "roundend" }

-- The fight log keeps at most this many lines (the latest): a player away for long keeps
-- guarding, and the log the clock's lines.
encounter.LOG_LINES = 60

local function log_line(entry)
	return encounter.PARTS[entry[1]] .. "\t" .. tostring(entry[2]):gsub("[\t\n]", " ")
end

local function trimmed(out)
	if #out <= encounter.LOG_LINES then return table.concat(out, "\n") end
	return table.concat(out, "\n", #out - encounter.LOG_LINES + 1)
end

-- Lines (round.lines, round.advance: { { part, line }, ... }) as fights.log text:
-- "<paragraph>\t<line>" per line.
function encounter.log_of(lines)
	local out = {}
	for _, e in ipairs(lines) do out[#out + 1] = log_line(e) end
	return trimmed(out)
end

-- The log text with lines added after it (what the clock did since): a note about the
-- last command goes (it belonged to the page before).
function encounter.log_add(log, lines)
	if #lines == 0 then return log end
	local out = {}
	for line in tostring(log or ""):gmatch("[^\n]+") do
		local part = line:match("^([^\t]*)\t")
		if part ~= "note" and part ~= "stale" then out[#out + 1] = line end
	end
	for _, e in ipairs(lines) do out[#out + 1] = log_line(e) end
	return trimmed(out)
end

-- fights.log text -> { paragraphs = { { part = "yourturn" | "allyturn" | "monsterturn" |
-- "roundend", lines = { line, ... } }, ... } (in order: the lines of one part in a row make
-- a paragraph), note = text or nil, stale = true or nil }
function encounter.lines(log)
	local out = { paragraphs = {} }
	local last
	for part, line in tostring(log or ""):gmatch("([^\t\n]+)\t([^\n]*)") do
		if part == "note" then out.note = line
		elseif part == "stale" then out.stale = true
		else
			if not last or last.part ~= part then
				last = { part = part, lines = {} }
				out.paragraphs[#out.paragraphs + 1] = last
			end
			last.lines[#last.lines + 1] = line
		end
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

-- The player died in fight f (its log set by the caller: the lines that led to it): half
-- the gold, a quarter of the HP, back to town. The fight is kept as it ended (outcome
-- "death") for its page.
function encounter.die(user, f)
	local st = f.st
	local d = combat.death(st)
	-- fixed: legacy kept the uber buffs and didn't write currentmp, refunding the MP of a
	-- spell cast on the fatal turn. The fight (and its statuses) ends.
	f.outcome = "death"
	-- the monster's last word over the player, for the death page (fight/speech.lua)
	f.result = f.taunt and { taunt_by = f.taunt.by, taunt = f.taunt.text } or {}
	state.save(f)
	dk.db:exec([[UPDATE users SET currenthp = ?, currentmp = ?, currentaction = 'In Town', latitude = 0,
		longitude = 0, gold = ? WHERE id = ?]], d.currenthp, st.currentmp, d.gold, user.id)
end

-- The player won fight f (its log set by the caller: the lines that won it): the rewards
-- per defeated enemy (summed), a level-up or the drop roll (once per encounter), paid now;
-- the fight is kept with outcome "victory" and what GET /victory shows in fights.result.
-- `user`: the users row (as before the round: its experience and gold).
function encounter.win(user, f)
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
	if f.last_words then res.said_by, res.said = f.last_words.by, f.last_words.text end
	f.outcome, f.result = "victory", res
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
	if (res.said or "") ~= "" then ctx.said = { by = res.said_by or "", text = res.said } end
	ctx.dropped = res.dropped
	if (res.drop_note or "") ~= "" then ctx.drop_note = res.drop_note end   -- what became of the drop
	if res.levelup then
		ctx.levelup = { levels = res.levels, hp = res.hp, mp = res.mp, tp = res.tp, strength = res.strength,
			dexterity = res.dexterity, learned = res.learned }
		return "Courage and Wit have served thee well!", ctx
	end
	return "Victory!", ctx
end

-- An encounter begins for player `user_id`, marked Fighting by the caller (the row is read
-- again: the caller saved the position, and a move's world statuses may have changed the
-- HP): any older fight goes, a monster of the level band where they stand is picked (each
-- enemy's HP rolled), the weather's fields are up (fight/fields.lua), and when it is
-- quicker its first strike is played (an ambush). Saved.
-- Returns "fight" (go on fighting), "death" (the ambush killed the player: see
-- encounter.die), each with the monster's row, or nil when no monster can be met there
-- (nothing changed).
function encounter.begin(user_id)
	local user = game.user(user_id)
	local monster = encounter.pick(user.latitude, user.longitude)
	if not monster then
		dk.log("warn", string.format("no roaming monsters for an encounter at %d, %d", user.latitude, user.longitude))
		return nil
	end
	state.clear(user.id)
	-- the hotbar is fixed for the fight: actions new to it take their slots now
	hotbar.settle(user)
	local st = game.player(user)
	local f = state.new({ user_id = user.id, round = 1, st = st, tick = clock.tick(clock.now()) })
	state.add_monster(f, monster, 1)
	f.rand = rand
	f.max_allies = game.control().max_allies or 1
	fields.start(f, f.tick)
	-- the fight's voice: what its monsters say is picked by it, not by the dice
	f.data.voice = (os.time() * 7919 + math.floor((dk.clock() % 1) * 1000000)) % 2147483647
	local player_first = round.start(f)
	-- the monster's first words open the page (before its first strike, if it is quicker)
	local opening = {}
	f.out, f.part = opening, "player"
	speech.start(f)
	f.out, f.part = nil, nil
	if not player_first then
		local r = round.play(f, { kind = "ambush" })
		for i = #opening, 1, -1 do table.insert(r.player, 1, opening[i]) end
		f = r.f
		f.log = encounter.log_of(round.lines(r))
		if r.died then
			encounter.die(user, f)
			return "death", monster
		end
	else
		f.log = encounter.log_of(round.lines({ player = opening }))
	end
	round.next_turn(f)
	state.save(f)
	encounter.save_player(user.id, f.st)
	return "fight", monster
end

-- Advances fight f of users row `user` (in progress, f.rand set) to clock tick n
-- (round.advance; at most `limit` ticks), then settles what that did: the lines go into
-- the log, a death or a victory ends the fight (encounter.die, encounter.win), else the
-- fight and the player's numbers are saved when anything was played. The server's tick
-- (lib/tick.lua) and POST /fight (before its command) both come here. Returns the advance
-- (round.advance's: f the model after it, lines, ticks, changed, died / victory).
function encounter.advance(user, f, n, limit)
	local fresh = f.tick == 0
	local a = round.advance(f, n, limit)
	f = a.f
	if a.ticks == 0 and not fresh then return a end
	f.log = encounter.log_add(f.log, a.lines)
	if a.died then
		encounter.die(user, f)
	elseif a.victory then
		encounter.save_player(user.id, f.st)
		encounter.win(user, f)
	else
		state.save(f)
		encounter.save_player(user.id, f.st)
	end
	return a
end

return encounter
