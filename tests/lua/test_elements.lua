-- Unit tests for elements, resistances and wards (lib/elements.lua; docs/APP.md "Elements
-- and wards"): the damage formula (identity, clamps, immunity, absorbing, at least 1, the
-- battlefield's percent), the lines, and the combatant handles' API (lib/action.lua):
-- :hurt's return value and notes, :resist / :immune_to summed from every source, and
-- wards: 0 and 100 roll nothing, 1-99 roll exactly one die.
local action = require("lib.action")
local elements = require("lib.elements")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function no_rolls()
	error("no die may be rolled here", 2)
end

-- rand that answers `values` in order and records the ranges asked.
local function dice(values)
	local d = { calls = {} }
	d.rand = function(min, max)
		d.calls[#d.calls + 1] = min .. "," .. max
		return assert(table.remove(values, 1), "unexpected roll")
	end
	return d
end

function T.damage_formula()
	-- neutral, no resistance, no field: exactly n
	for _, n in ipairs({ 0, 1, 2, 7, 13, 250, 99999 }) do
		local dealt, healed = elements.damage(n, 0, 0)
		eq(dealt, n, "identity " .. n); eq(healed, 0)
	end
	eq(elements.damage(10, 0, 50), 5, "resists half")
	eq(elements.damage(15, 0, 50), 7, "rounded down")
	eq(elements.damage(10, 0, -50), 15, "a weakness")
	eq(elements.damage(10, 0, -100), 20, "the most weakness: double")
	eq(elements.damage(10, 0, -250), 20, "clamped to -100")
	local dealt, healed = elements.damage(10, 0, 100)
	eq(dealt, 0, "immune"); eq(healed, 0)
	dealt, healed = elements.damage(10, 0, 150)
	eq(dealt, 0, "absorbs"); eq(healed, 5, "the excess heals")
	dealt, healed = elements.damage(10, 0, 500)
	eq(dealt, 0); eq(healed, 10, "clamped to 200: heals it all")
	-- at least 1 unless resisted fully, and nothing from nothing
	eq(elements.damage(1, 0, 99), 1); eq(elements.damage(3, 0, 90), 1); eq(elements.damage(0, 0, 50), 0)
	-- the battlefield's percent first, then the resistance
	eq(elements.damage(10, 25, 0), 12); eq(elements.damage(10, -40, 0), 6); eq(elements.damage(10, -150, 0), 0)
	eq(elements.damage(10, 50, 50), 7, "scaled 15, then halved")
	eq(elements.damage(1, -50, 0), 0, "scaled to nothing: no minimum")
end

function T.clamps_and_names()
	eq(elements.clamp_resist(-300), -100); eq(elements.clamp_resist(250), 200); eq(elements.clamp_resist(40), 40)
	eq(elements.clamp_ward(-5), 0); eq(elements.clamp_ward(130), 100); eq(elements.clamp_ward(30), 30)
	assert(elements.valid("fire") and elements.valid("neutral") and not elements.valid("plasma"), "valid")
	eq(#elements.LIST, 11); eq(elements.KEYS[1], "neutral"); eq(elements.name("holy"), "Holy")
	eq(elements.ward_name("sleep"), "Sleep"); eq(elements.ward_name("uber_damage"), "Uber Damage")
	local s = elements.sum({ fire = 50 }, nil, { fire = -25, frost = 10 })
	eq(s.fire, 25); eq(s.frost, 10)
end

function T.lines()
	eq(elements.note("fire", 0, false), nil)
	eq(elements.note("fire", -50, false), "It is weak to fire!")
	eq(elements.note("frost", 30, false), "It resists frost.")
	eq(elements.note("arcane", 100, false), "It is immune to arcane force.")
	eq(elements.note("lightning", 150, false), "It absorbs the lightning!")
	eq(elements.note("fire", -50, true), "You are weak to fire!")
	eq(elements.note("frost", 30, true), "You resist frost.")
	eq(table.concat(elements.lines({ arcane = 100, frost = -50, fire = 25, lightning = 120, earth = 0 }, { sleep = 100,
		poison = 30, burning = 0 }), "|"),
		"Resists Fire (25%)|Weak to Frost (+50%)|Absorbs Lightning (20%)|Immune to Arcane|Wards off Poison (30%)|" ..
		"Wards off Sleep (100%)")
	eq(#elements.lines(nil, nil), 0)
end

---------------------------------------------------------------------------------------
-- The handles

-- Runs fn(s, h) as a status hook on a handle made from t (the caster and target; lines
-- worded for the player).
local function on(t, fn, rand)
	local h = action.combatant(t)
	local r = action.call({ kind = "status", entity = { key = "test", name = "Test" }, module = {}, caster = h, target = h, plain = true,
		in_fight = true, rand = rand or no_rolls, fn = function(s) return fn(s, h) end })
	assert(r.ok, tostring(r.err))
	return r, h
end

local MONSTER = { id = 2, side = "enemy", name = "Imp", hp = 50, maxhp = 100 }

local function with(over)
	local t = {}
	for k, v in pairs(MONSTER) do t[k] = v end
	for k, v in pairs(over or {}) do t[k] = v end
	return t
end

function T.hurt_returns_what_it_dealt()
	local r, h = on(with(), function(s, h)
		local n = h:hurt(10)
		s:say("Hit for %d.", n)
		return n
	end)
	eq(r.value, 10); eq(h.hp, 40); eq(table.concat(r.lines, "|"), "Hit for 10.")
	eq(#r.events, 2); eq(r.events[1].type, "hurt"); eq(r.events[1].amount, 10)
	-- resisted: what was dealt, and the line after the next one said
	r, h = on(with({ resist = { fire = 50 } }), function(s, h)
		local n = h:hurt(10, "fire")
		s:say("Burned for %d.", n)
		s:say("Then this.")
		return n
	end)
	eq(r.value, 5); eq(h.hp, 45); eq(table.concat(r.lines, "|"), "Burned for 5.|It resists fire.|Then this.")
	-- immune: nothing dealt
	r, h = on(with({ resist = { arcane = 100 } }), function(_, h) return h:hurt(30, "arcane") end)
	eq(r.value, 0); eq(h.hp, 50); eq(table.concat(r.lines, "|"), "It is immune to arcane force.", "a note without a line")
	-- absorbing heals instead (never above the maximum) and returns 0
	r, h = on(with({ resist = { lightning = 150 } }), function(_, h) return h:hurt(20, "lightning") end)
	eq(r.value, 0); eq(h.hp, 60); eq(r.events[1].type, "heal"); eq(r.events[1].amount, 10)
	r, h = on(with({ hp = 98, resist = { lightning = 200 } }), function(_, h) return h:hurt(20, "lightning") end)
	eq(r.value, 0); eq(h.hp, 100); eq(r.events[1].amount, 2)
	-- the player hears it in its own words
	r = on(with({ is_player = true, side = "player", resist = { frost = -50 } }), function(s, h)
		s:say("Ouch %d.", h:hurt(10, "frost"))
	end)
	eq(table.concat(r.lines, "|"), "Ouch 15.|You are weak to frost!")
	-- only elements
	local h0 = action.combatant(with())
	r = action.call({ kind = "spell", entity = { key = "t", name = "T" }, module = {}, caster = h0, target = h0,
		in_fight = true, rand = no_rolls, fn = function() h0:hurt(1, "plasma") end })
	eq(r.reason, "error"); assert(tostring(r.err):find("unknown element plasma", 1, true), tostring(r.err))
end

function T.resistances_add_up_from_every_source()
	local h = action.combatant(with({ resist = { fire = 100, frost = 30 }, statuses = {
		{ key = "thaw", name = "Thaw", kind = "harmful", data = {}, resist = { fire = -50 } },
		{ key = "chill", name = "Chill", kind = "helpful", data = {}, resist = { frost = 300 } } } }))
	eq(h:resist("fire"), 50); eq(h:immune_to("fire"), false)
	eq(h:resist("frost"), 200, "clamped"); eq(h:immune_to("frost"), true)
	eq(h:resist(), 0, "neutral by default"); eq(h:resist("holy"), 0)
	eq(h.attack_element, "neutral")
	local ok = pcall(function() return h:resist("plasma") end)
	eq(ok, false, "an unknown element is an error")
	eq(action.combatant(with({ attack_element = "fire" })).attack_element, "fire")
end

function T.wards_roll_only_when_uncertain()
	-- 0: always takes hold, no roll
	local r, h = on(with(), function(_, h) return h:afflict("poison", { ticks = 2 }) end)
	eq(r.value, true); eq(h:has_status("poison"), true)
	-- 100: never, no roll, nothing recorded
	r, h = on(with({ ward = { poison = 100 } }), function(_, h) return h:afflict("poison", { ticks = 2 }) end)
	eq(r.value, false); eq(h:has_status("poison"), false); eq(#r.events, 0)
	r, h = on(with({ ward = { sleep = 60 }, statuses = { { key = "x", name = "X", kind = "helpful", data = {},
		ward = { sleep = 70 } } } }), function(_, h) return h:sleep(5) end)
	eq(r.value, false, "summed and clamped to 100"); eq(h.asleep, false)
	-- 1-99: one die, rand(1, 100), resisted at or below the ward
	local d = dice({ 30 })
	r, h = on(with({ ward = { poison = 30 } }), function(_, h) return h:afflict("poison") end, d.rand)
	eq(r.value, false); eq(table.concat(d.calls, " "), "1,100"); eq(h:has_status("poison"), false)
	d = dice({ 31 })
	r, h = on(with({ ward = { poison = 30 } }), function(_, h) return h:afflict("poison") end, d.rand)
	eq(r.value, true); eq(#d.calls, 1); eq(h:has_status("poison"), true)
	d = dice({ 99 })
	r, h = on(with({ ward = { sleep = 50 } }), function(_, h) return h:sleep(4) end, d.rand)
	eq(r.value, true); eq(h.asleep, true); eq(#d.calls, 1)
	-- waking is no status taking hold: no roll, always works
	r, h = on(with({ ward = { sleep = 50 }, statuses = { { key = "sleep", name = "Asleep", kind = "harmful",
		data = { chance = 5 } } } }), function(_, h) return h:sleep(0) end)
	eq(r.value, true); eq(h.asleep, false)
	-- the reading
	h = action.combatant(with({ ward = { sleep = 40 } }))
	eq(h:ward("sleep"), 40); eq(h:ward("poison"), 0)
end

return T
