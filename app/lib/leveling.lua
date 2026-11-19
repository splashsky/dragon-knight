-- leveling.lua :: the experience curve, TP gains and HP milestones, as formulas.
--
-- The original game (1.1.11) listed every level's total experience, TP gain and HP gain
-- per class in its levels table. Those columns follow simple rules, fitted here to the
-- original table: the experience totals come within 0.44% of it (the rest is hand-tweaked
-- noise), and the TP and HP milestone gains match it exactly. The other per-level gains
-- (base HP, MP, strength, dexterity, spells) stay data in the `levels` table, editable in
-- the admin panel. Pure module (no DB access): edit the parameters below and the game
-- picks them up on the next request; tests/lua/test_leveling.lua compares them with a
-- frozen copy of the original table.
local leveling = {}

leveling.MAX_LEVEL = 100
-- Experience for the last level: the MEDIUMINT UNSIGNED ceiling of the original database.
-- Rewards stop just below it, so level MAX_LEVEL is never reached by fighting.
leveling.MAX_EXPERIENCE = 16777215

-- Experience curve per class (1 Mage, 2 Warrior, 3 Paladin). step(n) is the experience
-- from level n to level n + 1: step(1) = base, then each step is the previous one times
-- the stage's factor, rounded down (step(n) = floor(step(n - 1) * factor)). Stages apply
-- in order to steps 2, 3, ...; after the last stage the steps stay flat. exp_for(level) is
-- the sum of the steps below it (0 at level 1), except exp_for(MAX_LEVEL) = MAX_EXPERIENCE.
leveling.EXP = {
	[1] = { base = 15, stages = {
		{ factor = 2, steps = 2 }, { factor = 1.5, steps = 8 },
		{ factor = 1.25, steps = 5 }, { factor = 1.125, steps = 28 },
	} },
	[2] = { base = 18, stages = {
		{ factor = 2, steps = 2 }, { factor = 1.5, steps = 8 },
		{ factor = 1.25, steps = 5 }, { factor = 1.125, steps = 27 },
	} },
	[3] = { base = 20, stages = {
		{ factor = 2, steps = 2 }, { factor = 1.5, steps = 8 },
		{ factor = 1.25, steps = 6 }, { factor = 1.125, steps = 25 },
	} },
}

-- TP gained on reaching a level: base + floor(level / every), with exceptions. `start` is
-- the level 1 entry of the help page (the original table's; new characters get the users
-- table defaults). Nothing is gained at MAX_LEVEL.
leveling.TP = { start = 5, base = 2, every = 30, exceptions = { [2] = 1 } }

-- HP bonus on reaching a milestone level, added to the levels table's per-class HP gain
-- (which is 0 at these levels): every 10th level gets the bonus of the first band it falls
-- in (none past the last band), plus the extra levels listed.
leveling.HP_MILESTONES = {
	every = 10,
	bands = { { upto = 30, hp = 10 }, { upto = 60, hp = 15 }, { upto = 90, hp = 20 } },
	extra = { [99] = 50 },
}

local function params(class)
	local p = leveling.EXP[math.tointeger(tonumber(class))]
	assert(p, "bad class")
	return p
end

-- Per class (computed once per VM): the steps, steps[n] for n = 1 .. MAX_LEVEL - 2 (at
-- least), and the experience totals, totals[level] for level = 1 .. MAX_LEVEL.
local curves = {}

local function curve(class)
	local p = params(class)
	local c = curves[p]
	if c then return c end
	local steps = { p.base }
	for _, stage in ipairs(p.stages) do
		for _ = 1, stage.steps do steps[#steps + 1] = math.floor(steps[#steps] * stage.factor) end
	end
	while #steps < leveling.MAX_LEVEL - 2 do steps[#steps + 1] = steps[#steps] end
	local totals = { 0 }
	for level = 2, leveling.MAX_LEVEL - 1 do totals[level] = totals[level - 1] + steps[level - 1] end
	totals[leveling.MAX_LEVEL] = leveling.MAX_EXPERIENCE
	c = { steps = steps, totals = totals }
	curves[p] = c
	return c
end

-- Total experience needed to be at `level`; nil outside 1 .. MAX_LEVEL.
function leveling.exp_for(class, level)
	return curve(class).totals[level]
end

-- The curve's step from level n to n + 1 (n >= 1). The last level is the cap instead:
-- exp_for(MAX_LEVEL) is MAX_EXPERIENCE, not exp_for(MAX_LEVEL - 1) + step(MAX_LEVEL - 1).
function leveling.step(class, n)
	local steps = curve(class).steps
	return steps[n] or steps[#steps]
end

-- The highest level whose experience `exp` covers (1 .. MAX_LEVEL).
function leveling.level_for_exp(class, exp)
	local totals = curve(class).totals
	local level = 1
	while level < leveling.MAX_LEVEL and exp >= totals[level + 1] do level = level + 1 end
	return level
end

-- TP gained on reaching `level`.
function leveling.tp_gain(level)
	local tp = leveling.TP
	if level == 1 then return tp.start end
	if level >= leveling.MAX_LEVEL then return 0 end
	return tp.exceptions[level] or tp.base + level // tp.every
end

-- HP bonus on reaching `level` (0 unless it is a milestone).
function leveling.hp_bonus(level)
	local m = leveling.HP_MILESTONES
	if m.extra[level] then return m.extra[level] end
	if level % m.every ~= 0 then return 0 end
	for _, band in ipairs(m.bands) do
		if level <= band.upto then return band.hp end
	end
	return 0
end

return leveling
