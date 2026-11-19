-- content/load.lua :: reading and validating content files, and their fingerprint.
--
-- Files are app/<kind dir>/<key>.lua (listed with dk.list_modules, so new files count
-- without a restart). Each runs in an empty environment: a content file is plain data
-- (no globals, no require, no DB). Errors name the file.
local schema = require("lib.content.schema")

local load = {}

-- Bumped when the flat form or the sync changes meaning, to force a resync.
load.FORMAT = "dk-content-3"

function load.path(kind, key)
	return (dk.config.app_dir or "app") .. "/" .. kind.dir:gsub("%.", "/") .. "/" .. key .. ".lua"
end

-- Runs one content module in an empty environment; returns its value or nil, message.
local function run_file(module)
	local ok, loader = pcall(package.searchers[2], module)
	if not ok then return nil, tostring(loader) end
	if type(loader) ~= "function" then return nil, tostring(loader) end
	if debug.getupvalue(loader, 1) == "_ENV" then debug.setupvalue(loader, 1, {}) end
	local ok2, data = pcall(loader, module)
	if not ok2 then return nil, tostring(data) end
	return data
end

-- All files of one kind: { kind = spec, entities = { { key, flat }, ... } (sorted by key),
-- by_key = { key -> flat }, errors = { "path: message", ... } }.
function load.kind(name)
	local kind = schema.kind(name)
	local out = { kind = kind, entities = {}, by_key = {}, errors = {} }
	for _, module in ipairs(dk.list_modules(kind.dir)) do
		local key = module:sub(#kind.dir + 2)
		local path = load.path(kind, key)
		if not schema.valid_key(key) then
			out.errors[#out.errors + 1] = path .. ": the file name is the " .. kind.label ..
				"'s key and must be lowercase letters, digits and _ (like " .. kind.dir:match("[^.]+$") ..
				"/my_" .. kind.label .. ".lua)"
		else
			local data, err = run_file(module)
			local flat, errs
			if err then errs = { err } else flat, errs = schema.validate(kind, data) end
			if flat then
				out.entities[#out.entities + 1] = { key = key, flat = flat }
				out.by_key[key] = flat
			else
				for _, e in ipairs(errs) do
					-- loader errors already carry the path (chunk name)
					out.errors[#out.errors + 1] = e:find(key .. ".lua", 1, true) and e or (path .. ": " .. e)
				end
			end
		end
	end
	return out
end

-- References between kinds: every key in a "keys" field with `refs` (a class's
-- levels.N.spells) must be a file of that kind. Checked against the files, not the
-- database, so a reference to a deleted (retired) entity is an error too. Skipped while
-- the referenced kind has errors of its own (those are reported instead).
local function check_refs(all, k)
	for _, e in ipairs(k.entities) do
		local fields = {}
		for f in pairs(e.flat) do fields[#fields + 1] = f end
		table.sort(fields)
		for _, f in ipairs(fields) do
			local spec = k.kind.field(f)
			local target = spec and spec.type == "keys" and spec.refs and all.kinds[spec.refs]
			if target and #target.errors == 0 then
				for key in tostring(e.flat[f]):gmatch("[^,]+") do
					if not target.by_key[key] then
						k.errors[#k.errors + 1] = ("%s: %s: no %s '%s' (%s)"):format(load.path(k.kind, e.key), f,
							target.kind.label, key, load.path(target.kind, key))
					end
				end
			end
		end
	end
end

-- Every kind: { kinds = { name -> load.kind(name) }, errors = { ... } }.
function load.all()
	local all = { kinds = {}, errors = {} }
	for _, name in ipairs(schema.KINDS) do all.kinds[name] = load.kind(name) end
	for _, name in ipairs(schema.KINDS) do
		local k = all.kinds[name]
		check_refs(all, k)
		for _, e in ipairs(k.errors) do all.errors[#all.errors + 1] = e end
	end
	return all
end

local function serialize_value(v)
	if math.type(v) == "integer" then return "i" .. v end
	return "s" .. string.format("%q", tostring(v))
end

-- Canonical text of everything loaded: one line per kind/key/field, sorted.
function load.canonical(all)
	local lines = { load.FORMAT }
	for _, name in ipairs(schema.KINDS) do
		local k = all.kinds[name]
		for _, e in ipairs(k.entities) do
			local fields = {}
			for f in pairs(e.flat) do fields[#fields + 1] = f end
			table.sort(fields)
			for _, f in ipairs(fields) do
				lines[#lines + 1] = name .. "\t" .. e.key .. "\t" .. f .. "\t" .. serialize_value(e.flat[f])
			end
		end
	end
	return table.concat(lines, "\n")
end

-- sha256 (hex) of the canonical serialization.
function load.fingerprint(all)
	return dk.crypto.hex(dk.crypto.sha256(load.canonical(all)))
end

return load
