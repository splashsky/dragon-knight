-- Unit tests for app/lib/leveling.lua: the formulas against a frozen copy of the original
-- 1.1.11 levels table (tests/lua/levels_original.lua) and the seeded levels table.
local game = require("lib.game")
local leveling = require("lib.leveling")
local original = require("tests.levels_original")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local MAX = leveling.MAX_LEVEL

function T.parameters()
	eq(MAX, 100); eq(leveling.MAX_EXPERIENCE, 16777215)
	eq(leveling.step(1, 1), 15); eq(leveling.step(2, 1), 18); eq(leveling.step(3, 1), 20)
	eq(leveling.step(1, 2), 30); eq(leveling.step(1, 3), 60); eq(leveling.step(1, 4), 90)
	-- the flat steps at the top (the original table's: 126760, 135211, 148382)
	eq(leveling.step(1, 45), 126203); eq(leveling.step(1, 44), leveling.step(1, 43) * 9 // 8)
	eq(leveling.step(1, 98), 126203)
	eq(leveling.step(2, 44), 135042); eq(leveling.step(2, 98), 135042)
	eq(leveling.step(3, 43), 148227); eq(leveling.step(3, 98), 148227)
	for class = 1, 3 do
		eq(leveling.exp_for(class, 1), 0, "exp_for(1)")
		eq(leveling.exp_for(class, MAX), 16777215, "exp_for(100)")
		eq(leveling.exp_for(class, 0), nil); eq(leveling.exp_for(class, MAX + 1), nil)
		for level = 2, MAX - 1 do
			eq(leveling.exp_for(class, level), leveling.exp_for(class, level - 1) + leveling.step(class, level - 1),
				 "class " .. class .. " exp_for(" .. level .. ")")
		end
	end
	assert(not pcall(leveling.exp_for, 4, 2), "class 4 accepted")
end

function T.monotonic_and_round_trip()
	for class = 1, 3 do
		for level = 2, MAX do
			assert(leveling.exp_for(class, level) > leveling.exp_for(class, level - 1), "not increasing")
		end
		for level = 1, MAX do
			local exp = leveling.exp_for(class, level)
			eq(leveling.level_for_exp(class, exp), level, "level_for_exp(exp_for)")
			if level > 1 then eq(leveling.level_for_exp(class, exp - 1), level - 1, "just below") end
		end
		eq(leveling.level_for_exp(class, 10 ^ 9), MAX)
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

-- Every experience total within 0.5% of the original table, TP identical.
function T.matches_original_table()
	for class = 1, 3 do
		local o = original[class]
		for level = 1, MAX do
			local want, got = o.exp[level], leveling.exp_for(class, level)
			assert(math.abs(got - want) <= want * 0.005,
						 ("class %d level %d: exp %d, original %d"):format(class, level, got, want))
			eq(leveling.tp_gain(level), o.tp[level], ("class %d level %d tp"):format(class, level))
		end
		-- exact where the original follows the rule without tweaks
		eq(leveling.exp_for(class, 2), o.exp[2]); eq(leveling.exp_for(class, 3), o.exp[3])
	end
end

-- The seeded levels table's HP plus the milestone bonus is the original HP gain.
function T.seeded_hp_plus_bonus_is_original()
	local rows = dk.db:query("SELECT * FROM levels ORDER BY id")
	eq(#rows, MAX, "levels rows")
	for class = 1, 3 do
		for _, row in ipairs(rows) do
			eq(row[game.level_key(class, "hp")] + leveling.hp_bonus(row.id), original[class].hp[row.id],
				 ("class %d level %d hp"):format(class, row.id))
		end
	end
end

return T
