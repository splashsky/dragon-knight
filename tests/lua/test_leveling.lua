-- Unit tests for app/lib/leveling.lua with the class content files' parameters
-- (app/content/classes/{mage,warrior,paladin}.lua): the formulas against a frozen copy of
-- the original 1.1.11 levels table (tests/lua/levels_original.lua), and the synced
-- class_levels table. The three classes use the global experience stages (the original
-- Mage curve) with their own first step, so Warrior and Paladin follow the original table
-- only up to level 44 and 17.
local leveling = require("lib.leveling")
local load = require("lib.content.load")
local original = require("tests.levels_original")
local T = {}

-- original class number -> the content file's flat values (exp_base, exp_stages, levels.N.*)
local files = load.kind("classes").by_key
local CLASS = { files.mage, files.warrior, files.paladin }
local exp_for = function(class, level) return leveling.exp_for(CLASS[class], level) end
local step = function(class, n) return leveling.step(CLASS[class], n) end
local level_for_exp = function(class, exp) return leveling.level_for_exp(CLASS[class], exp) end

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local MAX = leveling.MAX_LEVEL

function T.parameters()
	eq(MAX, 100); eq(leveling.MAX_EXPERIENCE, 16777215)
	eq(step(1, 1), 15); eq(step(2, 1), 18); eq(step(3, 1), 20)
	eq(step(1, 2), 30); eq(step(1, 3), 60); eq(step(1, 4), 90)
	-- the flat steps at the top (the original table's: 126760, 135211, 148382)
	eq(step(1, 45), 126203); eq(step(1, 44), step(1, 43) * 9 // 8)
	eq(step(1, 98), 126203)
	eq(step(2, 43), 135042); eq(step(2, 44), 151922); eq(step(2, 98), 151922)
	eq(step(3, 43), 150049); eq(step(3, 44), 168805); eq(step(3, 98), 168805)
	for class = 1, 3 do
		eq(exp_for(class, 1), 0, "exp_for(1)")
		eq(exp_for(class, MAX), 16777215, "exp_for(100)")
		eq(exp_for(class, 0), nil); eq(exp_for(class, MAX + 1), nil)
		for level = 2, MAX - 1 do
			eq(exp_for(class, level), exp_for(class, level - 1) + step(class, level - 1),
				 "class " .. class .. " exp_for(" .. level .. ")")
		end
	end
	assert(not pcall(leveling.exp_for, nil, 2), "no class accepted")
	assert(not pcall(leveling.exp_for, { exp_base = 15, exp_stages = "2x" }, 2), "bad stages accepted")
	assert(not pcall(leveling.exp_for, { exp_base = 0, exp_stages = "" }, 2), "base 0 accepted")
	-- no stages of its own: the global curve; a flat curve is "1x1"
	eq(leveling.GLOBAL_STAGES, "2x2,1.5x8,1.25x5,1.125x28")
	for _, own in ipairs({ "", false }) do
		local c = { exp_base = 15, exp_stages = own or nil }
		eq(leveling.stages_of(c), leveling.GLOBAL_STAGES)
		for level = 1, MAX do eq(leveling.exp_for(c, level), exp_for(1, level), "global curve") end
	end
	eq(leveling.exp_for({ exp_base = 10, exp_stages = "1x1" }, 4), 30)
	eq(leveling.stages_of({ exp_base = 10, exp_stages = "3x1" }), "3x1")
	eq(leveling.exp_for({ exp_base = 10, exp_stages = "3x1" }, 4), 10 + 30 + 30)
end

function T.parse_stages()
	local st = leveling.parse_stages("2x2, 1.5x8")
	eq(#st, 2); eq(st[1].factor, 2); eq(st[1].steps, 2); eq(st[2].factor, 1.5); eq(st[2].steps, 8)
	eq(#leveling.parse_stages(""), 0)
	for _, bad in ipairs({ "2", "x2", "2x", "0.5x3", "2x0", "2x2,", "2x2,,1x1", 5 }) do
		eq(leveling.parse_stages(bad), nil, "parse_stages(" .. tostring(bad) .. ")")
	end
end

function T.monotonic_and_round_trip()
	for class = 1, 3 do
		for level = 2, MAX do
			assert(exp_for(class, level) > exp_for(class, level - 1), "not increasing")
		end
		for level = 1, MAX do
			local exp = exp_for(class, level)
			eq(level_for_exp(class, exp), level, "level_for_exp(exp_for)")
			if level > 1 then eq(level_for_exp(class, exp - 1), level - 1, "just below") end
		end
		eq(level_for_exp(class, 10 ^ 9), MAX)
	end
end

function T.tp_and_hp_rules()
	eq(leveling.tp_gain(1), 5); eq(leveling.tp_gain(2), 1); eq(leveling.tp_gain(3), 2)
	eq(leveling.tp_gain(29), 2); eq(leveling.tp_gain(30), 3); eq(leveling.tp_gain(60), 4)
	eq(leveling.tp_gain(99), 5); eq(leveling.tp_gain(100), 0)
	eq(leveling.hp_bonus(1), 0); eq(leveling.hp_bonus(9), 0); eq(leveling.hp_bonus(10), 10)
	eq(leveling.hp_bonus(30), 10); eq(leveling.hp_bonus(40), 15); eq(leveling.hp_bonus(60), 15)
	eq(leveling.hp_bonus(70), 20); eq(leveling.hp_bonus(90), 20); eq(leveling.hp_bonus(95), 0)
	eq(leveling.hp_bonus(99), 50); eq(leveling.hp_bonus(100), 0)
end

-- Experience totals within 0.5% of the original table (the Mage's at every level; the
-- Warrior's and Paladin's, which use the Mage's stages from their own first step, up to
-- the level where the original gave them their own stages), TP identical for all.
local ORIGINAL_UNTIL = { MAX, 44, 17 }

function T.matches_original_table()
	for class = 1, 3 do
		local o = original[class]
		for level = 1, MAX do
			local want, got = o.exp[level], exp_for(class, level)
			if level <= ORIGINAL_UNTIL[class] then
				assert(math.abs(got - want) <= want * 0.005,
							 ("class %d level %d: exp %d, original %d"):format(class, level, got, want))
			end
			eq(got, leveling.exp_for({ exp_base = CLASS[class].exp_base, exp_stages = leveling.GLOBAL_STAGES }, level),
				 ("class %d level %d: the global curve"):format(class, level))
			eq(leveling.tp_gain(level), o.tp[level], ("class %d level %d tp"):format(class, level))
		end
		eq(CLASS[class].exp_stages, "", "class " .. class .. " has no stages of its own")
		-- exact where the original follows the rule without tweaks
		eq(exp_for(class, 2), o.exp[2]); eq(exp_for(class, 3), o.exp[3])
	end
	-- past those levels they need more than the original (up to 10.6% and 10.4% at 99)
	assert(exp_for(2, 99) > original[2].exp[99] and exp_for(2, 99) <= original[2].exp[99] * 1.107)
	assert(exp_for(3, 99) > original[3].exp[99] and exp_for(3, 99) <= original[3].exp[99] * 1.105)
end

-- The class files' HP plus the milestone bonus is the original HP gain; the synced
-- class_levels table holds the files' values.
function T.class_hp_plus_bonus_is_original()
	for class = 1, 3 do
		for level = 2, MAX do
			eq(CLASS[class]["levels." .. level .. ".hp"] + leveling.hp_bonus(level), original[class].hp[level],
				 ("class %d level %d hp"):format(class, level))
		end
		local rows = dk.db:query("SELECT level, hp FROM class_levels WHERE class_id = ? ORDER BY level", class)
		eq(#rows, MAX - 1, "class_levels rows")
		for _, row in ipairs(rows) do
			eq(row.hp, CLASS[class]["levels." .. row.level .. ".hp"], ("class %d level %d synced hp"):format(class, row.level))
		end
	end
end

return T
