-- Unit tests for the server's tick (lib/tick.lua) on the database (rows in a savepoint,
-- dk.publish recorded): the fights due advanced (the most behind first, at most
-- tick.FIGHTS a run, the rest on the next), a fight's change told to its player's pages
-- (`stale` on user:<id>, no tab), the fights not due left alone (due at their deadline or
-- the weather's first change of their fields), `sky` every tick, world statuses counting
-- the clock (never the last hit point; waiting while the character fights).
local fields = require("fight.fields")
local game = require("lib.game")
local monsters = require("lib.monsters")
local state = require("fight.state")
local statuses = require("lib.statuses")
local tick = require("lib.tick")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local N = 400000000   -- a clock tick (unix time 4000000000, the e2e tests' clock)

local function with_db(fn)
	dk.db:exec("SAVEPOINT test_tick")
	local published, publish, fights = {}, dk.publish, tick.FIGHTS
	dk.publish = function(channel, event, data) published[#published + 1] = channel .. " " .. event .. " " .. data end
	local ok, err = pcall(fn, published)
	dk.publish, tick.FIGHTS = publish, fights
	dk.db:exec("ROLLBACK TO test_tick")
	dk.db:exec("RELEASE test_tick")
	if not ok then error(err, 0) end
end

local function user(name, action, hp)
	dk.db:exec("INSERT INTO users (username, email, charname, verify, currentaction, currenthp, base_maxhp) " ..
		"VALUES (?, ?, ?, '1', ?, ?, 100)", name, name .. "@example.com", name, action or "Fighting", hp or 100)
	return game.user(dk.db:value("SELECT id FROM users WHERE username = ?", name))
end

-- A fight of `u` against a Blue Slime with 100 HP, on the clock at tick t (its turn runs
-- out 3 ticks later; the world's fields up).
local function fight(u, t)
	local f = state.new({ user_id = u.id, round = 2, st = game.player(u), tick = t, deadline = t + 3 })
	local c = state.add_monster(f, monsters.get(1), 1)
	c.hp, c.maxhp = 100, 100
	fields.start(f, t)
	state.save(f)
	return f
end

local function row(u)
	return dk.db:first("SELECT round, tick, deadline, due, log FROM fights WHERE user_id = ?", u.id)
end

function T.fights_due_are_advanced_and_told()
	with_db(function(published)
		local a, b, c = user("tick_a"), user("tick_b"), user("tick_c")
		fight(a, N - 10)   -- the most behind
		fight(b, N - 5)
		local fc = fight(c, N)   -- not due: its turn runs out at N + 3
		-- due at its deadline (N + 3), or at the first tick before it at which the weather
		-- would change its fields (they follow the weather, which moves every tick:
		-- fight/fields.lua)
		local up, due = fields.world(fc, N), N + 3
		for k = N + 2, N + 1, -1 do
			local w = fields.world(fc, k)
			for _, g in ipairs({ "sky", "ground", "time", "terrain" }) do if w[g] ~= up[g] then due = k end end
		end
		eq(row(c).due, due, "due at its deadline, or the weather's first change of its fields")
		tick.FIGHTS = 1
		local out = tick.run(N * 10)
		eq(out.fights, 1, "one fight a run (tick.FIGHTS)")
		eq(row(a).tick, N, "the most behind first"); eq(row(b).tick, N - 5, "the rest waits")
		local ra = row(a)
		assert(ra.round > 2, "it guarded: " .. ra.round)
		assert(ra.log:find("You hesitate, and raise your guard.", 1, true), ra.log)
		eq(published[1], "user:" .. a.id .. " stale {\"tab\":\"\"}")
		out = tick.run(N * 10)
		eq(out.fights, 1); eq(row(b).tick, N, "the next run")
		eq(row(c).tick, N, "not due: untouched")
		out = tick.run(N * 10)
		eq(out.fights, 0, "nothing due")
		local stale, sky = 0, 0
		for _, p in ipairs(published) do
			if p:find(" stale ", 1, true) then stale = stale + 1 end
			if p == "sky sky {\"tick\":" .. N .. "}" then sky = sky + 1 end
		end
		eq(stale, 2, "a stale for each fight advanced"); eq(sky, 3, "the World Map's sky, every run (every tick)")
	end)
end

-- The fights due are read together: their players, gear and fights in a few queries, not
-- several per fight; each fight then costs its writes (the fight, its combatants, the
-- player's numbers) and little else.
function T.the_fights_due_are_read_together()
	with_db(function()
		local dbcount = require("lib.dbcount")
		dbcount.install()
		local list = {}
		for i = 1, 8 do
			list[i] = user("batch_" .. i)
			fight(list[i], N - 10)
		end
		require("lib.cache").clear()
		local before = dbcount.count()
		local out = tick.run(N * 10)
		local queries = dbcount.count() - before
		eq(out.fights, 8, "all advanced")
		for _, u in ipairs(list) do eq(row(u).tick, N, "advanced to the tick") end
		-- (a fight writes 4 statements; the run's own reads, the world statuses', the sky's
		-- and the weather's are a few dozen in all)
		print("tick: " .. queries .. " queries for 8 fights")
		assert(queries <= 8 * 5 + 30, "the fights' reads together: " .. queries .. " queries for 8 fights")
	end)
end

function T.world_statuses_count_the_clock()
	with_db(function(published)
		local regen = statuses.by_key("regen")
		local u = user("tick_w", "Exploring", 50)
		dk.db:exec("INSERT INTO user_statuses (user_id, status_id, position, ticks_left, data, tick) VALUES (?, ?, 1, 3, " ..
			"'amount=i:5', ?)", u.id, regen.id, N - 1)
		local out = tick.run(N * 10)
		eq(out.world, 1)
		eq(game.user(u.id).currenthp, 55); eq(dk.db:value("SELECT ticks_left FROM user_statuses WHERE user_id = ?", u.id), 2)
		eq(published[1], "user:" .. u.id .. " stale {\"tab\":\"\"}")
		eq(tick.run(N * 10).world, 0, "counted up to now")
		-- while the character fights, the ticks pass them by
		dk.db:exec("UPDATE users SET currentaction = 'Fighting' WHERE id = ?", u.id)
		tick.run((N + 5) * 10)
		eq(game.user(u.id).currenthp, 55); eq(dk.db:value("SELECT tick FROM user_statuses WHERE user_id = ?", u.id), N + 5)
		-- a status hurting outside fights never takes the last hit point
		dk.db:exec("UPDATE users SET currentaction = 'Exploring', currenthp = 3 WHERE id = ?", u.id)
		local burn = statuses.by_key("burning")
		dk.db:exec("INSERT INTO user_statuses (user_id, status_id, position, ticks_left, data, tick) VALUES (?, ?, 2, 5, " ..
			"'amount=i:7', ?)", u.id, burn.id, N + 5)
		tick.run((N + 7) * 10)
		eq(game.user(u.id).currenthp, 1, "not below 1")
	end)
end

return T
