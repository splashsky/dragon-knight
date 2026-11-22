-- community/help.lua :: the public help pages (port of help.php, help_items.php,
-- help_spells.php, help_monsters.php, help_levels.php). Legacy printed these as
-- standalone pages without the game frame, so they use the minimal layout (full width
-- via body.help, see community.css).
local classes = require("lib.classes")
local clock = require("lib.clock")
local elements = require("lib.elements")
local game = require("lib.game")
local items = require("lib.items")
local leveling = require("lib.leveling")
local monsters = require("lib.monsters")
local php = require("lib.php")
local spells = require("lib.spells")
local statuses = require("lib.statuses")
local summons = require("lib.summons")
local view = require("lib.view")

local help = {}

local function page(req, subtitle, template, ctx)
	local control = game.control()
	ctx.control = control
	ctx.gamename = control.gamename
	ctx.subtitle = subtitle
	return view.page(req, control.gamename .. " Help", template, ctx,
									 { layout = "minimal", nav = false, body_class = "help" })
end

local NUMBER_WORDS = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" }

-- Playable classes with their description lines (one bullet each) and lore.
function help.index(req)
	local list = {}
	for _, c in ipairs(classes.playable()) do
		local points = {}
		for line in (c.description .. "\n"):gmatch("([^\n]*)\n") do
			local point = php.trim(line)
			if point ~= "" then points[#points + 1] = point end
		end
		list[#list + 1] = { name = c.name, points = points, lore = c.lore }
	end
	return page(req, nil, "community/help/index", {
		classes = list, class_count = NUMBER_WORDS[#list] or tostring(#list),
	})
end

-- One table per item category (items.CATEGORIES order): gear with its power and modifiers,
-- drops with their monster level, consumables with their description and power.
function help.items(req)
	local groups, by_cat = {}, {}
	for _, cat in ipairs(items.CATEGORIES) do
		by_cat[cat] = { category = cat, heading = items.HEADINGS[cat], rows = {} }
		groups[#groups + 1] = by_cat[cat]
	end
	for _, it in ipairs(items.active()) do
		local g = by_cat[it.category] or by_cat.misc
		local power
		if it.slot == "weapon" or it.attack ~= 0 then
			power = it.attack .. " Attack Power"
		elseif it.slot == "armor" or it.slot == "shield" or it.defense ~= 0 then
			power = it.defense .. " Defense Power"
		end
		local special = items.special_lines(it)
		for _, l in ipairs(items.charge_lines(it)) do special[#special + 1] = l end
		g.rows[#g.rows + 1] = {
			item = it, image = ({ weapon = "weapon", armor = "armor", shield = "shield" })[it.slot],
			power = power, special = special,
		}
	end
	local out = {}
	for _, g in ipairs(groups) do
		if #g.rows > 0 then out[#out + 1] = g end
	end
	return page(req, "Items & Drops", "community/help/items", { groups = out })
end

-- How long a status or an ally lasts without a duration of its own: "30s" (nil: until
-- it ends, or the whole fight).
local function lasts(ticks)
	return ticks > 0 and clock.duration(ticks * clock.TICK) or nil
end

-- Name and description, MP cost and power (what a spell does is its file's code; the
-- description says it); then the statuses spells and items cause and the allies they call,
-- with how long they last.
function help.spells(req)
	local st, su = statuses.active(), summons.active()
	for _, s in ipairs(st) do s.lasts = lasts(s.ticks) end
	for _, s in ipairs(su) do s.lasts = lasts(s.ticks) end
	return page(req, "Spells", "community/help/spells", { spells = spells.active(), statuses = st, summons = su })
end

-- Every monster that isn't retired, with its stats and MP (with equipment counted: what
-- the fight uses), its resistances, weaknesses and wards, and for those that have them its
-- spells (its own, then its class's), items and equipment.
function help.monsters(req)
	local list = {}
	for _, row in ipairs(monsters.active()) do
		local m = monsters.effective(row)
		local lo = monsters.loadout(m)
		local loadout = {}
		local function add(label, names)
			if #names > 0 then loadout[#loadout + 1] = { label = label, text = table.concat(names, ", ") } end
		end
		local names, taught = {}, {}
		for _, e in ipairs(lo.spells) do
			if e.from_class then taught[#taught + 1] = e.spell.name else names[#names + 1] = e.spell.name end
		end
		add("Spells", names)
		local class = (m.class or "") ~= "" and classes.find(m.class)
		if class then add(class.name .. " spells", taught) end
		names = {}
		for _, e in ipairs(lo.items) do names[#names + 1] = e.item.name .. (e.stock and (" (" .. e.stock .. ")") or "") end
		add("Items", names)
		names = {}
		for _, e in ipairs(lo.equipment) do names[#names + 1] = e.item.name end
		add("Equipment", names)
		list[#list + 1] = { monster = m, affinities = elements.lines(m.resist, m.ward), loadout = loadout,
			special = m.roams == 0, free = m.uses_mp == 0 and #lo.spells > 0 }
	end
	return page(req, "Monsters", "community/help/monsters", { monsters = list })
end

-- Columns per class: HP (gain + milestone bonus), MP, TP (formula), Strength, Dexterity.
-- Level 1 shows the starting values (TP: the original table's, see leveling.TP) and spells.
function help.levels(req)
	local spell_names = {}
	for _, s in ipairs(dk.db:query("SELECT id, name FROM spells")) do spell_names[s.id] = s.name end
	local list = {}
	for _, c in ipairs(classes.active()) do
		local gains = classes.levels(c)
		local start = {}
		for _, s in ipairs(classes.start_spells(c)) do start[#start + 1] = s.name end
		local rows = {
			{ level = 1, exp = php.number_format(0), spells = start,
				stats = { c.start_hp, c.start_mp, leveling.tp_gain(1), c.start_strength, c.start_dexterity } },
		}
		-- legacy hides level 100 (the level cap: exp 16777215, no stat gains)
		for level = 2, leveling.MAX_LEVEL - 1 do
			local g = gains[level]
			if g then
				local spells = {}
				for _, id in ipairs(g.spells) do spells[#spells + 1] = spell_names[id] end
				rows[#rows + 1] = {
					level = level,
					exp = php.number_format(leveling.exp_for(c, level)),
					stats = { g.hp + leveling.hp_bonus(level), g.mp, leveling.tp_gain(level), g.strength, g.dexterity },
					spells = spells,
				}
			end
		end
		list[#list + 1] = { name = c.name, rows = rows }
	end
	return page(req, "Levels", "community/help/levels", { classes = list })
end

return help
