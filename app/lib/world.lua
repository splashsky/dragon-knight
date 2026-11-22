-- world.lua :: actions and statuses outside fights (docs/APP.md "Fight engine"): the player
-- alone in the fight model (fight/state.lua state.world) with the world statuses
-- (user_statuses: statuses with scope "world" or "both" applied outside a fight, like the
-- Regen Potion's). They tick on the game's clock while the character isn't fighting (the
-- server's tick advances them: lib/tick.lua), outlast fights and take no part in them.
local clock = require("lib.clock")
local engine = require("fight.engine")
local game = require("lib.game")
local php = require("lib.php")
local round = require("fight.round")
local state = require("fight.state")

local world = {}

local function save_player(user_id, st)
	dk.db:exec("UPDATE users SET currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
		php.mysql_uint(st.currenthp), php.mysql_uint(st.currentmp), php.mysql_uint(st.currenttp), user_id)
end

-- The player handle (lib/action.lua) of model f for an out-of-fight spell or item.
function world.player(f)
	return engine.handle(f, state.player(f))
end

-- A model of `user` outside fights (st: game.player(user)) at the clock's tick now (what a
-- status applied to it counts from); rand: php.rand-like.
function world.load(user, st, rand)
	local f = state.world(user, st, clock.tick(clock.now()))
	f.rand = rand or php.rand
	return f
end

-- Applies a spell's or item's result (action.perform: r.events) to f and saves the
-- player's HP, MP, TP and world statuses. Returns the lines (the action's, then those of
-- the statuses it applied).
function world.apply(f, r)
	local lines = {}
	for _, l in ipairs(r.lines) do lines[#lines + 1] = l end
	f.out = lines
	engine.apply(f, r.events, state.player(f))
	save_player(f.user_id, f.st)
	state.save_world(f)
	return lines
end

-- The world statuses of users row `user` count the clock up to tick n (lib/tick.lua): each
-- ticks and counts down on every tick after the last it counted (at most `limit` ticks
-- now, the rest for the next call; at most round.CATCHUP behind; one not on the clock yet,
-- tick 0, starts on it at n). Statuses can't take the last hit point outside a fight.
-- While the character fights they wait: the ticks pass them by. Returns whether any
-- status counted a tick (the lines aren't shown).
function world.advance(user, n, rand, limit)
	if user.currentaction == "Fighting" then
		dk.db:exec("UPDATE user_statuses SET tick = ? WHERE user_id = ? AND tick < ?", n, user.id, n)
		return false
	end
	local f = world.load(user, game.player(user), rand)
	local p = state.player(f)
	local from = n
	for _, s in ipairs(p.statuses) do
		if s.tick == 0 then s.tick = n end
		from = math.min(from, s.tick)
	end
	if from >= n then
		state.save_world(f)
		return false
	end
	f.out = {}
	local start = math.max(from, n - round.CATCHUP)
	local last = limit and math.min(n, start + limit) or n
	for k = start + 1, last do
		if #p.statuses == 0 then break end
		f.tick = k
		engine.budget(f)
		engine.tick(f, p, k)
		if f.st.currenthp < 1 then f.st.currenthp = 1 end
	end
	for _, s in ipairs(p.statuses) do s.tick = math.max(s.tick, last) end
	save_player(user.id, f.st)
	state.save_world(f)
	return true
end

return world
