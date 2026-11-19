-- admin/editor.lua :: generic "edit one row" form: field specs -> form values,
-- legacy-style validation, and a whitelisted UPDATE.
--
-- spec = {
--   table = "items",              -- fixed SQL identifier (never from the request)
--   heading = "Edit Items",       -- page title / legacy <b><u>heading</u></b>
--   saved = "Item updated.",      -- message after a successful save
--   grouped = false,              -- true: all "required" checks first, then "numeric"
--                                 -- (legacy edituser/editlevel order); else per field
--   validate = function(v, errors) end,   -- extra checks after the field checks
--   after_save = function(req, row, v) end,  -- after the UPDATE
--   notes = "admin/notes_x",      -- optional template rendered under the form
--   intro = "text",               -- optional text above the form
--   path, column, list_intro, none -- list page (admin/crud.lua): URL, name column, texts
--   fields = { field, ... },
-- }
-- field = {
--   name = "buycost",             -- form field name
--   column = "buycost",           -- DB column (default: name); nil for kind "password"
--   label = "Cost",               -- escaped on output
--   kind = "text" | "select" | "static" | "separator" | "password",
--   int = true,                   -- storage conversion (default: text as typed)
--   required = "Cost is required.", numeric = "Cost must be a number.",
--   empty = { "", " " },          -- values that count as missing for `required`
--   default = "X", default_if = { "", " " },   -- replaced before validation
--   options = { { 1, "Weapon" }, ... },        -- select: anything else is rejected
--   size, maxlength, suffix, help (trusted HTML), highlight, format = "datetime"
--   virtual = true,               -- a text field that is not a column: shown as get(row),
--   get = function(row) end,      -- read from the form, saved by the spec's after_save
--                                 -- (with kind = "static": shown only)
-- }
local common = require("admin.common")
local php = require("lib.php")

local editor = {}

local function stored(f)
	return f.kind ~= "static" and f.kind ~= "separator" and f.kind ~= "password" and not f.virtual
end

local function column(f)
	return f.column or f.name
end

local function quote(ident)
	assert(ident:find("^[%w_]+$"), "bad identifier")
	return '"' .. ident .. '"'
end

local function in_list(list, v)
	for _, x in ipairs(list) do
		if x == v then return true end
	end
	return false
end

local function option_ok(f, v)
	for _, o in ipairs(f.options) do
		if tostring(o[1]) == v then return true end
	end
	return false
end

-- Form values for a DB row (all strings).
function editor.values_from_row(spec, row)
	local v = {}
	for _, f in ipairs(spec.fields) do
		if f.virtual then
			v[f.name] = f.get(row)
		elseif f.kind ~= "separator" and f.kind ~= "password" then
			local raw = row[column(f)]
			if f.format == "datetime" then
				v[f.name] = (raw and raw ~= 0) and php.datetime(raw) or "Never"
			else
				v[f.name] = common.str(raw)
			end
		end
	end
	return v
end

-- Reads ONLY the spec's editable fields from the request (no mass assignment).
function editor.values_from_form(spec, req)
	local v = {}
	for _, f in ipairs(spec.fields) do
		if stored(f) or f.kind == "password" or (f.virtual and f.kind ~= "static") then
			local s = common.field(req, f.name)
			if f.default and in_list(f.default_if or { "" }, s) then s = f.default end
			v[f.name] = s
		end
	end
	return v
end

local function check_required(f, v, errors)
	if f.required and in_list(f.empty or { "" }, v[f.name]) then
		errors[#errors + 1] = f.required
	end
end

local function check_numeric(f, v, errors)
	if f.numeric and not common.is_numeric(v[f.name]) then
		errors[#errors + 1] = f.numeric
	end
end

local function check_option(f, v, errors)
	if f.kind == "select" and not option_ok(f, v[f.name]) then
		errors[#errors + 1] = f.invalid or (f.label .. " is invalid.")
	end
end

-- Returns the list of error messages (empty when valid), in legacy order.
function editor.validate(spec, v)
	local errors = {}
	local fields = {}
	for _, f in ipairs(spec.fields) do
		if stored(f) then fields[#fields + 1] = f end
	end
	if spec.grouped then
		for _, f in ipairs(fields) do check_required(f, v, errors) end
		for _, f in ipairs(fields) do check_numeric(f, v, errors) end
	else
		for _, f in ipairs(fields) do
			check_required(f, v, errors)
			check_numeric(f, v, errors)
		end
	end
	if spec.validate then spec.validate(v, errors) end
	for _, f in ipairs(fields) do check_option(f, v, errors) end
	return errors
end

local function convert(f, s)
	if f.int then return common.to_int(s) end
	return s
end

-- UPDATE <table> SET <whitelisted columns> WHERE id = ?
function editor.update(spec, id, v)
	local sets, params = {}, {}
	for _, f in ipairs(spec.fields) do
		if stored(f) then
			sets[#sets + 1] = quote(column(f)) .. " = ?"
			params[#params + 1] = convert(f, v[f.name])
		end
	end
	params[#params + 1] = id
	dk.db:exec("UPDATE " .. quote(spec.table) .. " SET " .. table.concat(sets, ", ") ..
						 " WHERE id = ?", table.unpack(params))
end

-- Renders the form page.
-- opts: action (URL), values, errors, saved (bool)
function editor.render(req, spec, opts)
	return common.page(req, spec.heading, "admin/form", {
		heading = spec.heading,
		intro = spec.intro,
		notes = spec.notes,
		fields = spec.fields,
		action = opts.action,
		values = opts.values,
		errors = (opts.errors and #opts.errors > 0) and opts.errors or nil,
		saved = opts.saved and spec.saved or nil,
	})
end

return editor
