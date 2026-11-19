-- tests/lua/fight_model.lua :: test helpers between the fight as the original game kept it
-- (the users row copy with currentmonsterhp, currentmonstersleep, currentmonsterimmune,
-- currentuberdamage, currentuberdefense) and the fight model (app/fight/state.lua): the
-- same mapping schema version 8 migrated fights in progress with.
local engine = require("fight.engine")
local state = require("fight.state")

local M = {}

local FIGHT = { currentmonster = true, currentmonsterhp = true, currentmonstersleep = true,
	currentmonsterimmune = true, currentuberdamage = true, currentuberdefense = true, currentfight = true }

-- A fight model from old-style row `st` against `monster` (a monsters row).
function M.model(st, monster, rand)
	local p = {}
	for k, v in pairs(st) do
		if not FIGHT[k] then p[k] = v end
	end
	local f = state.new({ user_id = st.id or 1, round = 2, st = p })
	f.rand = rand
	local c = state.add_monster(f, monster, 1)
	c.hp = st.currentmonsterhp or 0
	c.data.immune = st.currentmonsterimmune or 0
	if (st.currentmonstersleep or 0) ~= 0 then engine.afflict(f, c, "sleep", { chance = st.currentmonstersleep }) end
	local pl = state.player(f)
	if (st.currentuberdamage or 0) ~= 0 then engine.afflict(f, pl, "uber_damage", { pct = st.currentuberdamage }) end
	if (st.currentuberdefense or 0) ~= 0 then engine.afflict(f, pl, "uber_defense", { pct = st.currentuberdefense }) end
	return f
end

-- The old-style row of model f (its first enemy).
function M.flat(f)
	local out = {}
	for k, v in pairs(f.st) do out[k] = v end
	local c = state.side(f, "enemy", true)[1]
	local p = state.player(f)
	local function status(x, key, field)
		for _, s in ipairs(x.statuses) do
			if s.key == key then return s.data[field] end
		end
		return 0
	end
	if c then
		out.currentmonster = c.entity_id
		out.currentmonsterhp = c.hp
		out.currentmonsterimmune = c.data.immune
		out.currentmonstersleep = status(c, "sleep", "chance")
	end
	out.currentuberdamage = status(p, "uber_damage", "pct")
	out.currentuberdefense = status(p, "uber_defense", "pct")
	return out
end

return M
