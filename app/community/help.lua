-- community/help.lua :: the public help pages (port of help.php, help_items.php,
-- help_spells.php, help_monsters.php, help_levels.php). Legacy printed these as
-- standalone pages without the game frame, so they use the minimal layout (full width
-- via body.help, see community.css).
local classes = require("lib.classes")
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
		g.rows[#g.rows + 1] = {
			item = it, image = ({ weapon = "weapon", armor = "armor", shield = "shield" })[it.slot],
			power = power, special = items.special_lines(it),
		}
	end
	local out = {}
	for _, g in ipairs(groups) do
		if #g.rows > 0 then out[#out + 1] = g end
	end
	return page(req, "Items & Drops", "community/help/items", { groups = out })
end

-- Name and description, MP cost and power (what a spell does is its file's code; the
-- description says it); then the statuses spells and items cause and the allies they call.
function help.spells(req)
	return page(req, "Spells", "community/help/spells", {
		spells = spells.active(), statuses = statuses.active(), summons = summons.active(),
	})
end

-- Every monster that isn't retired, with its stats and MP (with equipment counted: what
-- the fight uses), and for those that have them their spells, items and equipment.
function help.monsters(req)
	local list = {}
	for _, row in ipairs(monsters.active()) do
		local m = monsters.effective(row)
		local immune
		if m.immune == 1 then immune = "Hurt" elseif m.immune ~= 0 then immune = "Hurt & Sleep" end
		local lo = monsters.loadout(m)
		local loadout = {}
		local function add(label, names)
			if #names > 0 then loadout[#loadout + 1] = { label = label, text = table.concat(names, ", ") } end
		end
		local names = {}
		for _, e in ipairs(lo.spells) do names[#names + 1] = e.spell.name end
		add("Spells", names)
		names = {}
		for _, e in ipairs(lo.items) do names[#names + 1] = e.item.name .. (e.stock and (" (" .. e.stock .. ")") or "") end
		add("Items", names)
		names = {}
		for _, e in ipairs(lo.equipment) do names[#names + 1] = e.item.name end
		add("Equipment", names)
		list[#list + 1] = { monster = m, immune = immune, loadout = loadout, special = m.roams == 0,
			free = m.uses_mp == 0 and #lo.spells > 0 }
	end
	return page(req, "Monsters", "community/help/monsters", { monsters = list })
end

-- Columns per class: HP (gain + milestone bonus), MP, TP (formula), Strength, Dexterity.
-- Level 1 shows the starting values (TP: the original table's, see leveling.TP).
function help.levels(req)
	local spell_names = {}
	for _, s in ipairs(dk.db:query("SELECT id, name FROM spells")) do spell_names[s.id] = s.name end
	local list = {}
	for _, c in ipairs(classes.active()) do
		local gains = classes.levels(c)
		local rows = {
			{ level = 1, exp = php.number_format(0), spells = {},
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
