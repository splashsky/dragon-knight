-- content/load.lua :: reading and validating content files, and their fingerprint.
--
-- Files are app/<kind dir>/<key>.lua (listed with dk.list_modules, so new files count
-- without a restart). Each runs in a restricted environment (lib/content/sandbox.lua:
-- math, string, table and a few safe functions; no dk, require, io, os, no DB). A file
-- returns a table of data, plus functions for the scripted kinds (spells, items, statuses,
-- summons: lib/content/scripted.lua). Errors name the file.
local sandbox = require("lib.content.sandbox")
local schema = require("lib.content.schema")

local load = {}

-- Bumped when the flat form or the sync changes meaning, to force a resync.
load.FORMAT = "dk-content-7"

function load.path(kind, key)
	return (dk.config.app_dir or "app") .. "/" .. kind.dir:gsub("%.", "/") .. "/" .. key .. ".lua"
end

-- Runs one content module in a fresh restricted environment; returns the table it
-- returned, or nil and a message.
local function run_file(module)
	local ok, loader = pcall(package.searchers[2], module)
	if not ok then return nil, tostring(loader) end
	if type(loader) ~= "function" then return nil, tostring(loader) end
	if debug.getupvalue(loader, 1) == "_ENV" then debug.setupvalue(loader, 1, sandbox.env()) end
	local ok2, data = sandbox.call(loader, module)
	if not ok2 then
		local msg = tostring(data)
		return nil, msg:match("^(.-)\nstack traceback:") or msg
	end
	return data
end

-- sha256 (hex) of a file's source, or "" when it can't be read: the fingerprint covers
-- the code too, so an edit that changes only behaviour is noticed.
local function source_hash(path)
	local f = io.open(path, "rb")
	if not f then return "" end
	local text = f:read("a")
	f:close()
	return dk.crypto.hex(dk.crypto.sha256(text or ""))
end

-- All files of one kind: { kind = spec, entities = { { key, flat, source }, ... } (sorted
-- by key; source: the hash of the file), by_key = { key -> flat }, modules = { key -> the
-- table the file returned }, errors = { "path: message", ... } }.
function load.kind(name)
	local kind = schema.kind(name)
	local out = { kind = kind, entities = {}, by_key = {}, modules = {}, errors = {} }
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
				out.entities[#out.entities + 1] = { key = key, flat = flat, source = source_hash(path) }
				out.by_key[key] = flat
				out.modules[key] = data
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
-- levels.N.spells) must be a file of that kind; then the kind's own validate_refs (a
-- monster's equipment must be gear of the slot's category, ...). Checked against the
-- files, not the database, so a reference to a deleted (retired) entity is an error too.
-- Skipped while the referenced kind has errors of its own (those are reported instead).
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
		if k.kind.validate_refs then
			k.kind.validate_refs(e.flat, all, function(msg)
				k.errors[#k.errors + 1] = load.path(k.kind, e.key) .. ": " .. msg
			end)
		end
	end
end

-- The loaded module (the table its file returned, functions included) of one valid
-- entity, for running its behaviour (lib/action.lua), or nil and why not. Loaded once per
-- VM (that is, per request).
local modules = {}

function load.module(kind_name, key)
	modules[kind_name] = modules[kind_name] or {}
	local cached = modules[kind_name][key]
	if cached then return cached.data, cached.err end
	local kind = schema.kind(kind_name)
	local data, err
	if not schema.valid_key(key) then
		err = "bad key"
	else
		data, err = run_file(kind.dir .. "." .. key)
		if data ~= nil then
			local ok, errs = schema.validate(kind, data)
			if not ok then data, err = nil, table.concat(errs, "; ") end
		end
	end
	modules[kind_name][key] = { data = data, err = err and (load.path(kind, key) .. ": " .. err) }
	return data, modules[kind_name][key].err
end

-- Primes (or with nil clears) the loaded module of an entity for this VM, as if its file
-- returned `data`: unit tests run statuses and summons without files.
function load.preload(kind_name, key, data)
	modules[kind_name] = modules[kind_name] or {}
	modules[kind_name][key] = data ~= nil and { data = data } or nil
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
			lines[#lines + 1] = name .. "\t" .. e.key .. "\t#source\t" .. (e.source or "")
		end
	end
	return table.concat(lines, "\n")
end

-- sha256 (hex) of the canonical serialization.
function load.fingerprint(all)
	return dk.crypto.hex(dk.crypto.sha256(load.canonical(all)))
end

return load
