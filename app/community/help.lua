-- community/help.lua :: the public help pages (port of help.php, help_items.php,
-- help_spells.php, help_monsters.php, help_levels.php). Legacy printed these as
-- standalone pages without the game frame, so they use the minimal layout (full width
-- via body.help, see community.css).
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

function help.index(req)
	local c = game.control()
	return page(req, nil, "community/help/index", {
		classes = { c.class1name, c.class2name, c.class3name },
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

-- Columns per class: HP (table gain + milestone bonus), MP, TP (formula), Strength, Dexterity.
function help.levels(req)
	local spell_names = {}
	for _, s in ipairs(dk.db:query("SELECT id, name FROM spells")) do spell_names[s.id] = s.name end
	local levels = dk.db:query("SELECT * FROM levels ORDER BY id")
	local classes = {}
	for class = 1, 3 do
		local rows = {}
		for _, lv in ipairs(levels) do
			-- legacy hides level 100 (the level cap: exp 16777215, no stat gains)
			if lv.id ~= leveling.MAX_LEVEL then
				local function gain(stat) return lv[game.level_key(class, stat)] end
				local spell = gain("spells")
				local exp = leveling.exp_for(class, lv.id)
				rows[#rows + 1] = {
					level = lv.id,
					exp = exp and php.number_format(exp),
					stats = {
						gain("hp") + leveling.hp_bonus(lv.id), gain("mp"), leveling.tp_gain(lv.id),
						gain("strength"), gain("dexterity"),
					},
					has_spell = spell ~= 0,
					spell = spell_names[spell],
				}
			end
		end
		classes[class] = { name = game.class_name(class), rows = rows }
	end
	return page(req, "Levels", "community/help/levels", { classes = classes })
end

return help
