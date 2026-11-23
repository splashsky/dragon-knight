-- cli/content.lua :: `dk content sync|status` -- content files (app/content/) vs. the
-- database (lib/content/sync.lua). `dk install` and `dk migrate` call sync_or_fail().
local schema = require("lib.content.schema")
local sync = require("lib.content.sync")

local USAGE = [[
usage: dk content sync|status

	sync     load and validate every content file (app/content/<kind>/<key>.lua) and
	         update the database now: new keys are added, changed values updated,
	         keys without a file retired, admin overrides re-applied. The running game
	         does the same on the next request after a file changes.
	status   show the files, database rows and overrides per kind, whether the database
	         is in sync with the files, and any errors; change nothing
]]

local content = {}

local function summary(report)
	local parts = {}
	for _, name in ipairs(schema.KINDS) do
		local r = report[name]
		local line = ("%s: %d, %d new, %d retired"):format(name, r.updated + r.inserted, r.inserted, r.retired)
		if r.unretired > 0 then line = line .. (", %d restored"):format(r.unretired) end
		if r.adopted > 0 then line = line .. (", %d earlier admin edits kept as overrides"):format(r.adopted) end
		parts[#parts + 1] = line
	end
	return table.concat(parts, "; ")
end

-- Syncs or raises (so the CLI's transaction rolls back).
function content.sync_or_fail(cmd)
	local report, err = sync.run()
	if not report then
		error(cmd .. ": the content files are invalid (nothing was changed); fix them and run again:\n" .. err, 0)
	end
	print("Content synced (" .. summary(report) .. ").")
	for _, s in ipairs(report.skipped) do print("warning: " .. s) end
	return report
end

local function status()
	local st = sync.status()
	for _, k in ipairs(st.kinds) do
		print(("%s: %d files, %d in the database (%d retired), %d overrides"):format(
			k.name, k.files, k.active + k.retired, k.retired, k.overrides))
	end
	if #st.errors > 0 then
		print("Content files have errors (the game keeps the last good content):")
		for _, e in ipairs(st.errors) do print("  " .. e) end
		return 1
	end
	if st.in_sync then
		print("The database is in sync with the content files (fingerprint " .. st.fingerprint:sub(1, 16) .. ").")
	else
		print("The database is not in sync with the content files: the next request or dk content sync updates it.")
	end
	return 0
end

function content.run(...)
	require("lib.dbcount").install()   -- (writes seen by the request cache, lib/cache.lua)
	local args = { ... }
	local cmd = args[1]
	if #args ~= 1 or cmd == "-h" or cmd == "--help" or (cmd ~= "sync" and cmd ~= "status") then
		if cmd == "-h" or cmd == "--help" then
			io.write(USAGE)
			return 0
		end
		io.stderr:write(USAGE)
		return 2
	end
	local migrations = require("lib.migrations")
	if migrations.current() ~= migrations.VERSION then
		io.stderr:write("dk content: the database schema is not current; run dk migrate (or dk install).\n")
		return 1
	end
	if cmd == "status" then return status() end
	content.sync_or_fail("dk content sync")
	return 0
end

return content
