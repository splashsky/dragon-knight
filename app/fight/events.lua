-- fight/events.lua :: a round as the JSON fight API's list of events (docs/APP.md "Fight
-- API"), built from the round's trace (fight/engine.lua "The trace"). Pure: no DB.
--
-- An event is one line of the fight page (`text`, exactly as the page shows it, in the
-- page's order) with what changed with it, or a change without a line:
--
--   { part = "player" | "allies" | "enemies" | "ending",   -- the page's paragraph
--     actor = "player" | "ally" | "enemy", actor_id, actor_name,   -- who acts (a status: its bearer)
--     type = "attack" | "spell" | "item" | "status" | "summon" | "blocked" | "run" | "ambush"
--            | "wave" | "say" (any other line) | "victory" | "death" | "escape" (the outcome),
--     text,                                     -- absent for a change without a line
--     hp = { { who, id, name, from, to, max } },   -- who: "player" | "ally" | "enemy"
--     mp = { ... }, tp = { ... },               -- (an enemy's MP only where the page shows it)
--     status = { { who, id, name, key, status, turns, change = "add" | "remove" | "expire"
--                | "turns", statuses = { { key, name, turns } } } },  -- statuses: after it
--     summon = { { change = "join" | "leave" | "turns", id, name, hp, max, turns } } }
--
-- Lists are present only when not empty; turns is absent when a status has no limit (or
-- an ally stays for the whole fight). Changes go with the step's latest line: a line, then
-- what it did; a change in a step that said nothing yet is an event without text.
local json = require("lib.json")

local events = {}

local function copy_list(list)
	local out = json.array()
	for i, s in ipairs(list or {}) do out[i] = { key = s.key, name = s.name, turns = s.turns } end
	return out
end

-- The events of trace (a round's r.f.trace). opts.hide_mp(id): true for an enemy whose MP
-- the page doesn't show (its MP changes are left out).
function events.build(trace, opts)
	opts = opts or {}
	local out, cur = {}, nil
	local function new(x)
		local d = x.doing or {}
		cur = { part = x.part, actor = d.side, actor_id = d.id, actor_name = d.name, type = d.type or "say",
			step = d.step or 0 }
		out[#out + 1] = cur
		return cur
	end
	local function event_of(x)
		local step = x.doing and x.doing.step or 0
		if cur and cur.step == step then return cur end
		return new(x)
	end
	local function add(x, field, item)
		local e = event_of(x)
		e[field] = e[field] or {}
		e[field][#e[field] + 1] = item
	end
	for _, x in ipairs(trace or {}) do
		if x.line then
			new(x).text = x.line
		elseif x.change then
			local hidden = x.change == "mp" and x.side == "enemy" and opts.hide_mp and opts.hide_mp(x.id)
			if not hidden then
				add(x, x.change, { who = x.side, id = x.id, name = x.name, from = x.from, to = x.to, max = x.max })
			end
		elseif x.status then
			add(x, "status", { who = x.side, id = x.id, name = x.name, key = x.key, status = x.label, turns = x.turns,
				change = x.status == "error" and "remove" or x.status, statuses = copy_list(x.list) })
		elseif x.summon then
			add(x, "summon", { change = x.summon, id = x.id, name = x.name, hp = x.hp, max = x.max, turns = x.turns })
		end
	end
	for _, e in ipairs(out) do e.step = nil end
	return out
end

-- The outcome as a last event: "victory", "death" or "escape" (no text: the page that
-- follows says it). player: the player's combatant id and name.
function events.outcome(list, kind, id, name)
	list[#list + 1] = { type = kind, actor = "player", actor_id = id, actor_name = name }
	return list
end

-- The texts of the events, in order (what the page's paragraphs show).
function events.lines(list)
	local out = {}
	for _, e in ipairs(list) do
		if e.text then out[#out + 1] = e.text end
	end
	return out
end

return events
