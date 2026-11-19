-- cli/migrate.lua :: `dk migrate` -- upgrade an existing database to the current schema
-- (steps in app/lib/migrations.lua). Runs in the CLI's transaction: on any error nothing
-- is changed.
local migrations = require("lib.migrations")

local USAGE = [[
usage: dk migrate [--status]

	Upgrades the database to the schema of this version of the game. All steps run in
	one transaction: if one fails, the database is left as it was.
	--status   print the database's and the game's schema versions; change nothing
]]

local function run(...)
	local status_only = false
	for _, a in ipairs({ ... }) do
		if a == "--status" then
			status_only = true
		elseif a == "-h" or a == "--help" then
			io.write(USAGE)
			return 0
		else
			io.stderr:write("dk migrate: unknown argument: ", a, "\n\n", USAGE)
			return 2
		end
	end
	if not migrations.installed() then
		io.stderr:write("dk migrate: the database has no Dragon Knight tables; run dk install.\n")
		return 1
	end

	local from, to = migrations.current(), migrations.VERSION
	if status_only then
		print(string.format("Database schema version %d; this game uses version %d%s.", from, to,
												from < to and " (run dk migrate)" or ""))
		return 0
	end
	if from > to then
		io.stderr:write(string.format("dk migrate: the database schema (version %d) is newer than " ..
																	"this game's (version %d); upgrade the game.\n", from, to))
		return 1
	end
	if from == to then
		print(string.format("Database schema is up to date (version %d).", to))
		return 0
	end
	for v = from + 1, to do
		local step = migrations.STEPS[v]
		print(string.format("Migrating to version %d: %s", v, step.name))
		step.up()
		migrations.stamp(v)
	end
	local bad = dk.db:query("PRAGMA foreign_key_check")
	if #bad > 0 then
		error(string.format("foreign key check failed after migrating (%d rows, first in table %s)",
												#bad, tostring(bad[1].table)), 0)
	end
	print(string.format("Database schema is now version %d.", to))
	return 0
end

return { run = run }
