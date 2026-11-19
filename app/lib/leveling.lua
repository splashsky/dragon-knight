-- leveling.lua :: the experience curve, TP gains and HP milestones, as formulas.
--
-- The original game (1.1.11) listed every level's total experience, TP gain and HP gain
-- per class in its levels table. Those columns follow simple rules, fitted here to the
-- original table: the Mage's experience totals come within 0.44% of it (the rest is
-- hand-tweaked noise), and the TP and HP milestone gains match it exactly. The experience
-- curve's stages are global (GLOBAL_STAGES, the original Mage curve; a class may define
-- its own); its first step and the other per-level gains (base HP, MP, strength,
-- dexterity, spells) are per class, in the class content files (app/content/classes/
-- *.lua). Pure module (no DB access): edit the rules below and the game picks them up on
-- the next request; tests/lua/test_leveling.lua compares them with a frozen copy of the
-- original table.
local leveling = {}

leveling.MAX_LEVEL = 100
-- Experience for the last level: the MEDIUMINT UNSIGNED ceiling of the original database.
-- Rewards stop just below it, so level MAX_LEVEL is never reached by fighting.
leveling.MAX_EXPERIENCE = 16777215

-- Experience curve: per class, from the class's content file (app/content/classes/
-- <key>.lua, synced into the classes table): `exp_base` and, rarely, `exp_stages` (empty
-- or absent: GLOBAL_STAGES). step(n) is the experience from level n to level n + 1:
-- step(1) = base, then each step is the previous one times the stage's factor, rounded
-- down (step(n) = floor(step(n - 1) * factor)). Stages ("2x2,1.5x8,1.25x5,1.125x28":
-- factor x steps) apply in order to steps 2, 3, ...; after the last stage the steps stay
-- flat (a class with a flat curve says "1x1"). exp_for(level) is the sum of the steps
-- below it (0 at level 1), except exp_for(MAX_LEVEL) = MAX_EXPERIENCE. `class` arguments
-- below are tables with those two fields (a classes row or a content entity).

-- The stages of every class that has none of its own (the original Mage curve).
leveling.GLOBAL_STAGES = "2x2,1.5x8,1.25x5,1.125x28"

-- The stages `class` levels by: its own, or GLOBAL_STAGES when it has none ("" or nil).
function leveling.stages_of(class)
	local own = class.exp_stages
	if own == nil or own == "" then return leveling.GLOBAL_STAGES end
	return own
end

-- "2x2,1.5x8" -> { { factor = 2, steps = 2 }, { factor = 1.5, steps = 8 } }, or nil and
-- an error message. "" means no stages (flat from the start).
function leveling.parse_stages(s)
	if type(s) ~= "string" then return nil, "must be a string like \"2x2,1.5x8\"" end
	local stages = {}
	if s == "" then return stages end
	for part in (s .. ","):gmatch("([^,]*),") do
		local f, n = part:match("^%s*([%d%.]+)x(%d+)%s*$")
		local factor, steps = tonumber(f), math.tointeger(tonumber(n))
		if not factor or not steps or factor < 1 or steps < 1 then
			return nil, "bad stage \"" .. part .. "\" (want factor x steps, e.g. \"1.5x8\", factor >= 1)"
		end
		stages[#stages + 1] = { factor = factor, steps = steps }
	end
	return stages
end

-- TP gained on reaching a level: base + floor(level / every), with exceptions. `start` is
-- the level 1 entry of the help page (the original table's; new characters get their
-- class's start_tp). Nothing is gained at MAX_LEVEL.
leveling.TP = { start = 5, base = 2, every = 30, exceptions = { [2] = 1 } }

-- HP bonus on reaching a milestone level, added to the class's per-level HP gain
-- (which is 0 at these levels): every 10th level gets the bonus of the first band it falls
-- in (none past the last band), plus the extra levels listed.
leveling.HP_MILESTONES = {
	every = 10,
	bands = { { upto = 30, hp = 10 }, { upto = 60, hp = 15 }, { upto = 90, hp = 20 } },
	extra = { [99] = 50 },
}

-- Per curve (computed once per VM): the steps, steps[n] for n = 1 .. MAX_LEVEL - 2 (at
-- least), and the experience totals, totals[level] for level = 1 .. MAX_LEVEL.
local curves = {}

local function curve(class)
	assert(type(class) == "table", "bad class")
	local base = math.tointeger(class.exp_base)
	local text = leveling.stages_of(class)
	local stages = leveling.parse_stages(text)
	assert(base and base >= 1 and stages, "bad class experience parameters")
	local id = base .. "|" .. text
	local c = curves[id]
	if c then return c end
	local steps = { base }
	for _, stage in ipairs(stages) do
		for _ = 1, stage.steps do steps[#steps + 1] = math.floor(steps[#steps] * stage.factor) end
	end
	while #steps < leveling.MAX_LEVEL - 2 do steps[#steps + 1] = steps[#steps] end
	local totals = { 0 }
	for level = 2, leveling.MAX_LEVEL - 1 do totals[level] = totals[level - 1] + steps[level - 1] end
	totals[leveling.MAX_LEVEL] = leveling.MAX_EXPERIENCE
	c = { steps = steps, totals = totals }
	curves[id] = c
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
