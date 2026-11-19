-- community/help.lua :: the public help pages (port of help.php, help_items.php,
-- help_spells.php, help_monsters.php, help_levels.php). Legacy printed these as
-- standalone pages without the game frame, so they use the minimal layout (full width
-- via body.help, see community.css).
local classes = require("lib.classes")
local game = require("lib.game")
local leveling = require("lib.leveling")
local php = require("lib.php")
local view = require("lib.view")

local help = {}

local SPECIAL_NAMES = {
	maxhp = "Max HP", maxmp = "Max MP", maxtp = "Max TP",
	goldbonus = "Gold Bonus (%)", expbonus = "Experience Bonus (%)",
	strength = "Strength", dexterity = "Dexterity",
	attackpower = "Attack Power", defensepower = "Defense Power",
}

local SPELL_TYPES = { "Heal", "Hurt", "Sleep", "+Damage (%)", "+Defense (%)" }

-- "maxhp,10" -> "Max HP +10"; "X" -> nil (shown as a light "None").
function help.special(s)
	if s == "X" then return nil end
	local parts = php.explode(",", s)
	local value = parts[2] or ""
	local n = tonumber(value)
	if n and n > 0 then value = "+" .. value end
	return (SPECIAL_NAMES[parts[1]] or parts[1]) .. " " .. value
end

local function page(req, subtitle, template, ctx)
	local control = game.control()
	ctx.control = control
	ctx.gamename = control.gamename
	ctx.subtitle = subtitle
	return view.page(req, control.gamename .. " Help", template, ctx,
									 { layout = "minimal", nav = false, body_class = "help" })
end

local NUMBER_WORDS = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" }

-- Playable classes with their description lines (one bullet each).
function help.index(req)
	local list = {}
	for _, c in ipairs(classes.playable()) do
		local points = {}
		for line in (c.description .. "\n"):gmatch("([^\n]*)\n") do
			local point = php.trim(line)
			if point ~= "" then points[#points + 1] = point end
		end
		list[#list + 1] = { name = c.name, points = points }
	end
	return page(req, nil, "community/help/index", {
		classes = list, class_count = NUMBER_WORDS[#list] or tostring(#list),
	})
end

function help.items(req)
	local items = {}
	for _, it in ipairs(dk.db:query("SELECT * FROM items ORDER BY id")) do
		local image, power = "shield", "Defense"
		if it.type == 1 then image, power = "weapon", "Attack"
		elseif it.type == 2 then image = "armor" end
		items[#items + 1] = { item = it, image = image, power = power, special = help.special(it.special) }
	end
	local drops = {}
	for _, d in ipairs(dk.db:query("SELECT * FROM drops ORDER BY id")) do
		drops[#drops + 1] = { drop = d, attr1 = help.special(d.attribute1), attr2 = help.special(d.attribute2) }
	end
	return page(req, "Items & Drops", "community/help/items", { items = items, drops = drops })
end

function help.spells(req)
	local spells = {}
	for _, s in ipairs(dk.db:query("SELECT * FROM spells ORDER BY id")) do
		-- legacy left $type unset (showing the previous row's type) for unknown types
		spells[#spells + 1] = { spell = s, type = SPELL_TYPES[s.type] or "" }
	end
	return page(req, "Spells", "community/help/spells", { spells = spells })
end

function help.monsters(req)
	local monsters = {}
	for _, m in ipairs(dk.db:query("SELECT * FROM monsters ORDER BY id")) do
		local immune
		if m.immune == 1 then immune = "Hurt" elseif m.immune ~= 0 then immune = "Hurt & Sleep" end
		monsters[#monsters + 1] = { monster = m, immune = immune }
	end
	return page(req, "Monsters", "community/help/monsters", { monsters = monsters })
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
