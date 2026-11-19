-- world.lua :: actions and statuses outside fights (docs/APP.md "Fight engine"): the player
-- alone in the fight model (fight/state.lua state.world) with the world statuses
-- (user_statuses: statuses with scope "world" or "both" applied outside a fight, like the
-- Regen Potion's). They tick on map moves, one move one turn; they outlast fights and
-- take no part in them.
local engine = require("fight.engine")
local game = require("lib.game")
local php = require("lib.php")
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

-- A model of `user` outside fights (st: game.player(user)); rand: php.rand-like.
function world.load(user, st, rand)
	local f = state.world(user, st)
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

-- One map move of users row `user`: the world statuses tick and count down (statuses can't
-- take the last hit point outside a fight). Costs one query without world statuses.
-- Returns the lines (not shown yet: the move redirects to the map).
function world.move(user, rand)
	if not dk.db:value("SELECT 1 FROM user_statuses WHERE user_id = ? LIMIT 1", user.id) then return {} end
	local f = world.load(user, game.player(user), rand)
	local lines = {}
	f.out = lines
	f.ticks = 0
	engine.world_move(f)
	if f.st.currenthp < 1 then f.st.currenthp = 1 end
	save_player(user.id, f.st)
	state.save_world(f)
	return lines
end

return world
