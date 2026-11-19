-- actors.lua :: the game's combatants as action handles (lib/action.lua) and applying an
-- action's events back to the game state. The state is the player's users row copy
-- (game.player: effective stats under the original column names) holding the fight too,
-- as in the original game: currentmonsterhp, currentmonstersleep, currentmonsterimmune,
-- currentuberdamage, currentuberdefense. Pure (no DB): callers save the row.
local action = require("lib.action")

local actors = {}

-- The player of users row copy `st`.
function actors.player(st)
	return action.combatant({
		side = "player", is_player = true, name = st.charname, level = st.level,
		hp = st.currenthp, maxhp = st.maxhp, mp = st.currentmp, maxmp = st.maxmp, tp = st.currenttp, maxtp = st.maxtp,
		attack = st.attackpower, defense = st.defensepower, strength = st.strength, dexterity = st.dexterity,
		uber_damage = st.currentuberdamage, uber_defense = st.currentuberdefense,
		can = { buff = true },
	})
end

-- The monster the player fights (`monster`: its monsters row; its HP, sleep and immunity
-- in this fight are on `st`). Monsters have no MP or TP yet.
function actors.monster(st, monster)
	return action.combatant({
		side = "monster", is_player = false, name = monster.name, level = monster.level,
		hp = st.currentmonsterhp, maxhp = monster.maxhp, attack = monster.maxdam, defense = monster.armor,
		immune = st.currentmonsterimmune, sleep_chance = st.currentmonstersleep,
		can = { sleep = true },
	})
end

-- side -> stat -> the column of `st` holding it
local COLUMNS = {
	player = { hp = "currenthp", mp = "currentmp", tp = "currenttp" },
	monster = { hp = "currentmonsterhp" },
}

local function add(st, side, stat, n)
	local col = COLUMNS[side] and COLUMNS[side][stat]
	if col then st[col] = st[col] + n end
end

-- Applies the events of an action (action.perform) to `st`, in order.
function actors.apply(st, events)
	for _, e in ipairs(events) do
		if e.type == "heal" then
			add(st, e.side, e.stat, e.amount)
		elseif e.type == "hurt" then
			add(st, e.side, "hp", -e.amount)
		elseif e.type == "spend" then
			add(st, e.side, e.stat, -e.amount)
		elseif e.type == "buff" and e.side == "player" then
			st["currentuber" .. e.kind] = e.pct
		elseif e.type == "sleep" and e.side == "monster" then
			st.currentmonstersleep = e.chance
		end
	end
	return st
end

return actors
