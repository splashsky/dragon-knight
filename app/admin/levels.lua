-- admin/levels.lua :: /admin/levels (legacy admin.php levels() + editlevel()).
local common = require("admin.common")
local editor = require("admin.editor")
local game = require("lib.game")
local php = require("lib.php")
local view = require("lib.view")

local levels = {}

local CLASS_WORDS = { "one", "two", "three" }
local STATS = {
	{ "exp", "Experience", 10, 8 }, { "hp", "HP", 5, 5 }, { "mp", "MP", 5, 5 },
	{ "tp", "TP", 5, 5 }, { "strength", "Strength", 5, 5 }, { "dexterity", "Dexterity", 5, 5 },
	{ "spells", "Spells", 5, 3 },
}

-- Form fields one_exp .. three_spells map to the whitelisted columns "1_exp" .. "3_spells"
-- (game.level_key). Labels use the class names; messages say "Class N" like legacy.
local function spec()
	local fields = { { name = "id", label = "ID", kind = "static" } }
	for class = 1, 3 do
		fields[#fields + 1] = { kind = "separator" }
		local cname = game.class_name(class) or ("Class " .. class)
		for _, st in ipairs(STATS) do
			fields[#fields + 1] = {
				name = CLASS_WORDS[class] .. "_" .. st[1],
				column = game.level_key(class, st[1]),
				label = cname .. " " .. st[2],
				size = st[3], maxlength = st[4], int = true,
				required = "Class " .. class .. " " .. st[2] .. " is required.",
				numeric = "Class " .. class .. " " .. st[2] .. " must be a number.",
				group = class,
			}
		end
	end
	return {
		table = "levels", heading = "Edit Levels", saved = "Level updated.",
		intro = "Experience values for each level should be the cumulative total amount of " ..
						"experience up to this point. All other values should be only the new amount to " ..
						"add this level.",
		fields = fields,
	}
end

-- legacy: per class, all "required" checks then all "numeric" checks.
local function validate(s, v)
	local errors = {}
	for class = 1, 3 do
		for _, f in ipairs(s.fields) do
			if f.group == class and v[f.name] == "" then errors[#errors + 1] = f.required end
		end
		for _, f in ipairs(s.fields) do
			if f.group == class and not common.is_numeric(v[f.name]) then errors[#errors + 1] = f.numeric end
		end
	end
	return errors
end

-- GET /admin/levels: legacy offered levels 2 .. (highest - 1) -- level 1 (starting stats)
-- and the last row (the 16777215-exp cap) are left alone; kept. ?level=N jumps to /N.
function levels.index(req)
	local pick = math.tointeger(tonumber(req.query.level or ""))
	if pick then return view.redirect("/admin/levels/" .. pick) end
	local top = dk.db:value("SELECT id FROM levels ORDER BY id DESC LIMIT 1") or 0
	local options = {}
	for i = 2, top - 1 do options[#options + 1] = i end
	return common.page(req, "Edit Levels", "admin/levels", { options = options })
end

local function row_for(id)
	return dk.db:first("SELECT * FROM levels WHERE id = ?", id)
end

local function action(id) return "/admin/levels/" .. id end

function levels.edit(req, params)
	local row = row_for(params.id)
	if not row then return common.message(req, "Edit Levels", "No level to edit.", 404) end
	local s = spec()
	return editor.render(req, s, { action = action(row.id), values = editor.values_from_row(s, row),
																 saved = req.query.saved ~= nil })
end

function levels.save(req, params)
	local row = row_for(params.id)
	if not row then return common.message(req, "Edit Levels", "No level to edit.", 404) end
	local s = spec()
	local v = editor.values_from_form(s, req)
	local errors = validate(s, v)
	if #errors > 0 then
		v.id = php.str(row.id)
		return editor.render(req, s, { action = action(row.id), values = v, errors = errors })
	end
	editor.update(s, row.id, v)
	return view.redirect(action(row.id) .. "?saved=1")
end

return levels
