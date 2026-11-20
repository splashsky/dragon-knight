-- fight/state.lua :: the fight model and its persistence. A fight is an encounter: the
-- player, allies (summons) and enemies (monsters, in waves), each a combatant with its
-- statuses. It lives in the fights, fight_combatants and fight_statuses tables and is
-- loaded and saved once per request (in the request's transaction); the round pipeline
-- (fight/round.lua) and the engine (fight/engine.lua) work on the plain tables below, so
-- they are unit-testable without the database. Outside fights the same model, with the
-- player alone (state.world), carries the world statuses (user_statuses), which tick on
-- map moves.
--
-- f = { user_id, round, wave, data = {}, st (the game.player row copy: the player's
-- numbers), in_fight, combatants = { c, ... } (by id), next_id, outcome ("" in progress,
-- "victory", "death": a finished fight kept for its page, fight/encounter.lua), log (the
-- last round's lines, encounter.log_of), result = {} (a victory's rewards) }
-- c = { id, side ("player" | "ally" | "enemy"), kind ("player" | "monster" | "summon"),
-- entity_id, wave, hp, maxhp (nil for the player: st has them), mp, maxmp (monsters),
-- turns_left (summons), data = {} (a monster's immune and the stock of its items,
-- stock_<position>), row (the summons row; a monster's with its equipment counted:
-- lib/monsters.lua monsters.effective), statuses = { inst, ... } (in the order applied) }
-- inst = { status_id, key, row (statuses row), turns_left (nil: no limit), data (the params
-- it was applied with), applied_round, source (a combatant id), position }
-- Persisted values are names and plain data only (lib/action.lua action.params), never
-- code: a charged spell's release step is saved by name.
local monsters = require("lib.monsters")
local statuses = require("lib.statuses")
local summons = require("lib.summons")

local state = {}

---------------------------------------------------------------------------------------
-- Values as text: "name=value" lines; i: integers, s: text, b: booleans.

function state.encode(t)
	local keys = {}
	for k in pairs(t or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local lines = {}
	for _, k in ipairs(keys) do
		local v = t[k]
		local tag
		if math.type(v) == "integer" then tag = "i"
		elseif type(v) == "string" then tag = "s"
		elseif type(v) == "boolean" then tag = "b"; v = v and 1 or 0
		else error("fight data " .. tostring(k) .. ": only whole numbers, text and booleans are saved (got " .. type(v) .. ")") end
		lines[#lines + 1] = k .. "=" .. tag .. ":" .. tostring(v)
	end
	return table.concat(lines, "\n")
end

function state.decode(text)
	local out = {}
	for line in tostring(text or ""):gmatch("[^\n]+") do
		local k, tag, v = line:match("^([%a_][%w_]*)=([isb]):(.*)$")
		if k then
			if tag == "i" then out[k] = math.tointeger(tonumber(v))
			elseif tag == "b" then out[k] = v == "1"
			else out[k] = v end
		end
	end
	return out
end

---------------------------------------------------------------------------------------
-- The model

-- A new, empty model. o: { user_id, round, wave, st, in_fight (default true) }.
function state.new(o)
	local f = {
		user_id = o.user_id, round = o.round or 1, wave = o.wave or 1, data = o.data or {}, st = o.st,
		in_fight = o.in_fight ~= false, combatants = {}, next_id = 1, outcome = "", log = "", result = {},
	}
	state.add(f, { side = "player", kind = "player" })
	return f
end

-- Adds a combatant (its id: the next number). Returns it.
function state.add(f, c)
	c.id = c.id or f.next_id
	if c.id >= f.next_id then f.next_id = c.id + 1 end
	c.data = c.data or {}
	c.statuses = c.statuses or {}
	c.wave = c.wave or 0
	f.combatants[#f.combatants + 1] = c
	table.sort(f.combatants, function(a, b) return a.id < b.id end)
	return c
end

function state.get(f, id)
	for _, c in ipairs(f.combatants) do
		if c.id == id then return c end
	end
	return nil
end

function state.remove(f, c)
	for i, x in ipairs(f.combatants) do
		if x == c then table.remove(f.combatants, i) return end
	end
end

function state.player(f)
	for _, c in ipairs(f.combatants) do
		if c.side == "player" then return c end
	end
	return nil
end

function state.hp(f, c)
	if c.side == "player" then return f.st.currenthp end
	return c.hp
end

function state.alive(f, c)
	return state.hp(f, c) > 0
end

-- Combatants of a side in order (enemies: of `wave`, the current one by default), living
-- ones only unless `all`.
function state.side(f, side, all, wave)
	local out = {}
	for _, c in ipairs(f.combatants) do
		if c.side == side and (side ~= "enemy" or c.wave == (wave or f.wave)) and (all or state.alive(f, c)) then
			out[#out + 1] = c
		end
	end
	return out
end

function state.enemies(f) return state.side(f, "enemy") end
function state.allies(f) return state.side(f, "ally") end

-- The waves still to come after the current one, and whether every enemy is defeated.
function state.last_wave(f)
	local last = f.wave
	for _, c in ipairs(f.combatants) do
		if c.side == "enemy" and c.wave > last then last = c.wave end
	end
	return last
end

function state.won(f)
	local any = false
	for _, c in ipairs(f.combatants) do
		if c.side == "enemy" then
			any = true
			if state.alive(f, c) then return false end
		end
	end
	return any
end

-- The data key of the stock left of a monster's item entry (position in its file).
function state.stock_key(position)
	return "stock_" .. position
end

-- An enemy from a monsters row (its HP is rolled when the encounter starts; its MP and the
-- stock of its items are full).
function state.add_monster(f, monster, wave)
	local row = monsters.effective(monster)
	local data = { immune = monster.immune }
	for _, e in ipairs(monsters.loadout(row).items) do
		if e.stock then data[state.stock_key(e.position)] = e.stock end
	end
	return state.add(f, {
		side = "enemy", kind = "monster", entity_id = monster.id, wave = wave or 1, hp = 0, maxhp = row.maxhp,
		mp = row.maxmp, maxmp = row.maxmp, data = data, row = row,
	})
end

-- Plain copy of the model (rows and rand shared): the round works on it and the caller
-- keeps the original when the player's action is refused.
local function deep(v, seen)
	if type(v) ~= "table" then return v end
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, x in pairs(v) do
		if k == "row" or k == "rand" then out[k] = x else out[k] = deep(x, seen) end
	end
	return setmetatable(out, getmetatable(v))
end

function state.copy(f)
	return deep(f, {})
end

---------------------------------------------------------------------------------------
-- Persistence

-- Status instances of a query; those of a retired status (its file is gone, and with it
-- its code) end here.
local function status_rows(sql, ...)
	local out = {}
	for _, r in ipairs(dk.db:query(sql, ...)) do
		local row = statuses.get(r.status_id)
		if row and row.retired == 0 then
			out[#out + 1] = {
				status_id = r.status_id, key = row.key, row = row, turns_left = r.turns_left, data = state.decode(r.data),
				applied_round = r.applied_round or 0, source = r.source, position = r.position, combatant_id = r.combatant_id,
			}
		end
	end
	return out
end

-- The fight of users row `user` (st: game.player(user)), or nil when there is none. Enemies
-- whose monster is gone and summons whose row is gone are left out (they can't act).
function state.load(user, st)
	local fr = dk.db:first("SELECT * FROM fights WHERE user_id = ?", user.id)
	if not fr then return nil end
	local f = { user_id = user.id, round = fr.round, wave = fr.wave, data = state.decode(fr.data), st = st,
		in_fight = true, combatants = {}, next_id = 1, outcome = fr.outcome, log = fr.log,
		result = state.decode(fr.result) }
	local by_id = {}
	for _, r in ipairs(dk.db:query("SELECT * FROM fight_combatants WHERE user_id = ? ORDER BY id", user.id)) do
		local c = { id = r.id, side = r.side, kind = r.kind, entity_id = r.entity_id, wave = r.wave, hp = r.hp,
			maxhp = r.maxhp, mp = r.mp, maxmp = r.maxmp, turns_left = r.turns_left, data = state.decode(r.data),
			statuses = {} }
		if r.kind == "monster" then
			local m = monsters.get(r.entity_id)
			c.row = m and monsters.effective(m)
			-- a fight from before monsters had MP (schema version 8): full
			if m and c.maxmp == nil then c.maxmp = c.row.maxmp end
			if m and c.mp == nil then c.mp = c.maxmp end
		elseif r.kind == "summon" then
			c.row = summons.get(r.entity_id)
		end
		if r.kind == "player" or c.row then
			state.add(f, c)
			by_id[c.id] = c
		end
	end
	if not state.player(f) then state.add(f, { side = "player", kind = "player" }) end
	for _, s in ipairs(status_rows("SELECT * FROM fight_statuses WHERE user_id = ? ORDER BY combatant_id, position", user.id)) do
		local c = by_id[s.combatant_id]
		s.combatant_id = nil
		if c then c.statuses[#c.statuses + 1] = s end
	end
	return f
end

-- Writes the fight back (users' HP/MP/TP are the caller's: they belong to the users row).
function state.save(f)
	local uid = f.user_id
	dk.db:exec("INSERT INTO fights (user_id, round, wave, data, outcome, log, result) VALUES (?, ?, ?, ?, ?, ?, ?) " ..
		"ON CONFLICT (user_id) DO UPDATE SET round = excluded.round, wave = excluded.wave, data = excluded.data, " ..
		"outcome = excluded.outcome, log = excluded.log, result = excluded.result", uid, f.round, f.wave,
		state.encode(f.data), f.outcome or "", f.log or "", state.encode(f.result))
	dk.db:exec("DELETE FROM fight_combatants WHERE user_id = ?", uid)
	for _, c in ipairs(f.combatants) do
		local player = c.side == "player"
		dk.db:exec("INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, wave, hp, maxhp, turns_left, data, " ..
			"mp, maxmp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", uid, c.id, c.side, c.kind, c.entity_id, c.wave or 0,
			not player and c.hp or nil, not player and c.maxhp or nil, c.turns_left, state.encode(c.data),
			c.kind == "monster" and c.mp or nil, c.kind == "monster" and c.maxmp or nil)
		for i, s in ipairs(c.statuses) do
			dk.db:exec("INSERT INTO fight_statuses (user_id, combatant_id, status_id, position, turns_left, data, " ..
				"applied_round, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", uid, c.id, s.status_id, i, s.turns_left,
				state.encode(s.data), s.applied_round or 0, s.source)
		end
	end
end

-- No fight any more (an escape, a new encounter): its combatants and statuses go too.
function state.clear(user_id)
	dk.db:exec("DELETE FROM fights WHERE user_id = ?", user_id)
end

-- The player moves on (a map move, travel): a finished fight kept for its page goes.
function state.forget(user_id)
	dk.db:exec("DELETE FROM fights WHERE user_id = ? AND outcome <> ''", user_id)
end

-- The player outside fights, with the world statuses (user_statuses).
function state.world(user, st)
	local f = state.new({ user_id = user.id, round = 0, st = st, in_fight = false })
	local p = state.player(f)
	p.statuses = status_rows("SELECT * FROM user_statuses WHERE user_id = ? ORDER BY position", user.id)
	return f
end

function state.save_world(f)
	dk.db:exec("DELETE FROM user_statuses WHERE user_id = ?", f.user_id)
	for i, s in ipairs(state.player(f).statuses) do
		dk.db:exec("INSERT INTO user_statuses (user_id, status_id, position, turns_left, data) VALUES (?, ?, ?, ?, ?)",
			f.user_id, s.status_id, i, s.turns_left, state.encode(s.data))
	end
end

return state
