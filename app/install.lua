-- install.lua :: `dk install` -- create the schema, load the default game data and
-- create the administrator account (port of legacy install.php).
local auth = require("lib.auth")
local classes = require("lib.classes")
local content = require("cli.content")
local mail = require("lib.mail")
local migrations = require("lib.migrations")
local news = require("lib.news")
local php = require("lib.php")

local USAGE = [[
usage: dk install [--partial] [--force]
									[--admin <username> <email> <password>] [--charname NAME]
									[--class ID|KEY]

	--partial     create tables but load no game data except the control row, the
								forum boards, the first news post and the content (classes, spells,
								items, statuses, summons, monsters) (legacy "Partial Setup")
	--force       drop existing Dragon Knight tables first (DESTROYS ALL DATA)
	--admin       administrator account; prompted for when omitted
	--charname    administrator character name (default: the username)
	--class       character class, by id or key (default 1, mage)
]]

-- children before parents (foreign keys): sessions/news/forum before forum/forums/users,
-- user_spells/user_items/user_hotbar/town_items/class_levels/class_spells before
-- users/spells/items/towns/classes, the monster loadouts before monsters/items/spells, the fight tables and
-- user_statuses before users/statuses; "levels" (before schema version 4) and "drops" (before 6) are old tables
local TABLES = { "sessions", "babble", "control", "drops", "news", "forum", "forums", "user_items", "user_hotbar",
								 "town_items", "monster_equipment", "monster_items", "monster_spells", "items", "levels", "monsters", "user_spells", "class_levels", "class_spells",
								 "spells", "towns", "fight_statuses", "fight_combatants", "fights", "user_statuses", "users",
								 "classes", "statuses", "summons", "content_overrides", "content_adopt", "meta" }

local function read_file(path)
	local f, err = io.open(path, "rb")
	if not f then error("cannot read " .. tostring(err), 0) end
	local s = f:read("a")
	f:close()
	return s
end

local function parse_args(argv)
	local o = { class = "1" }
	local i = 1
	while i <= #argv do
		local a = argv[i]
		if a == "--partial" then o.partial = true
		elseif a == "--force" then o.force = true
		elseif a == "--admin" then
			o.username, o.email, o.password = argv[i + 1], argv[i + 2], argv[i + 3]
			if not o.password then return nil, "--admin needs <username> <email> <password>" end
			i = i + 3
		elseif a == "--charname" or a == "--class" then
			if not argv[i + 1] then return nil, a .. " needs a value" end
			o[a:sub(3)] = argv[i + 1]
			i = i + 1
		elseif a == "-h" or a == "--help" then
			o.help = true
		else
			return nil, "unknown argument: " .. a
		end
		i = i + 1
	end
	return o
end

local function prompt(label)
	io.write(label, ": ")
	io.flush()
	local line = io.read("l")
	if not line then error("no input (pass --admin <username> <email> <password>)", 0) end
	return php.trim(line)
end

local function admin_errors(o)
	local errs = {}
	if o.username == "" or o.username:find("[^A-z0-9_%-]") or #o.username > 30 then
		errs[#errs + 1] = "username must be 1-30 alphanumeric characters"
	end
	if o.charname == "" or o.charname:find("[^A-z0-9_%-]") or #o.charname > 30 then
		errs[#errs + 1] = "character name must be 1-30 alphanumeric characters"
	end
	if not php.is_email(o.email) then errs[#errs + 1] = "email isn't valid" end
	if php.trim(o.password) == "" then errs[#errs + 1] = "password is required" end
	if not o.class:find("^[%w_]+$") then errs[#errs + 1] = "class must be a class id or key" end
	return errs
end

local function existing_tables()
	local found = {}
	for _, t in ipairs(TABLES) do
		if dk.db:value("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", t) then
			found[#found + 1] = t
		end
	end
	return found
end

-- seed.sql has one INSERT per line; partial setup keeps only control + news (legacy
-- populated those two even for "Partial Setup"), the forum boards and the class, spell,
-- item, status and monster ids (structural: content keeps the original ids).
local function seed_sql(full, sql)
	if full then return sql end
	local keep = {}
	for line in sql:gmatch("[^\n]+") do
		if line:find("^INSERT INTO control ") or line:find("^INSERT INTO news ") or
				line:find("^INSERT INTO forums ") or line:find("^INSERT INTO classes ") or
				line:find("^INSERT INTO spells ") or line:find("^INSERT INTO items ") or
				line:find("^INSERT INTO statuses ") or line:find("^INSERT INTO monsters ") then
			keep[#keep + 1] = line
		end
	end
	return table.concat(keep, "\n")
end

local function run(...)
	local o, err = parse_args({ ... })
	if not o then
		io.stderr:write("dk install: ", err, "\n\n", USAGE)
		return 2
	end
	if o.help then
		io.write(USAGE)
		return 0
	end

	local found = existing_tables()
	if #found > 0 and not o.force then
		io.stderr:write("dk install: the database already has tables (", table.concat(found, ", "),
										").\nUse --force to drop them and start over (this destroys all data).\n")
		return 1
	end

	local app_dir = dk.config.app_dir or "app"
	local schema = read_file(app_dir .. "/sql/schema.sql")
	local seed = read_file(app_dir .. "/sql/seed.sql")

	if not o.username then
		print("Create the administrator account.")
		o.username = prompt("Username")
		o.email = prompt("Email")
		o.password = prompt("Password")
		if not o.charname then
			local c = prompt("Character name [" .. o.username .. "]")
			if c ~= "" then o.charname = c end
		end
	end
	o.charname = o.charname or o.username
	local errs = admin_errors(o)
	if #errs > 0 then
		io.stderr:write("dk install: ", table.concat(errs, "; "), "\n")
		return 1
	end

	-- everything below runs in the CLI's transaction: any error rolls it all back
	for _, t in ipairs(found) do dk.db:exec_script('DROP TABLE "' .. t .. '"') end
	dk.db:exec_script(schema)
	dk.db:exec_script(seed_sql(not o.partial, seed))
	migrations.stamp(migrations.VERSION)
	content.sync_or_fail("dk install")

	local class = classes.find(o.class)
	if not class or class.retired ~= 0 then
		local names = {}
		for _, c in ipairs(classes.active()) do names[#names + 1] = c.id .. " " .. c.key end
		error("dk install: no class '" .. o.class .. "' (classes: " .. table.concat(names, ", ") .. ")", 0)
	end
	local st = classes.start_stats(class)
	local now = dk.now()
	local _, id = dk.db:exec(
		"INSERT INTO users (username, password, email, verify, charname, charclass, regdate, onlinetime, " ..
		"authlevel, currenthp, base_maxhp, currentmp, base_maxmp, currenttp, base_maxtp, strength, dexterity) " ..
		"VALUES (?, ?, ?, '1', ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)",
		o.username, auth.hash_password(o.password), o.email, o.charname, class.id, now, now,
		st.currenthp, st.base_maxhp, st.currentmp, st.base_maxmp, st.currenttp, st.base_maxtp, st.strength,
		st.dexterity)
	classes.teach_start_spells(id, class)
	news.adopt({ id = id })

	print(string.format("Database %s created (%s setup).", dk.config.db_path or "data/dk.db",
											o.partial and "partial" or "complete"))
	print(string.format("Administrator '%s' created (user id %d).", o.username, id))

	if mail.ensure_outbox() then
		print("Outbox directory: " .. mail.outbox_dir())
	else
		io.stderr:write("warning: cannot create outbox directory " .. mail.outbox_dir() .. "\n")
	end

	if type(dk.config.secret) ~= "string" or dk.config.secret == "" then
		print("")
		print("config.lua has no secret. Add this line to it (keep it private):")
		print(string.format('  secret = "%s",', dk.crypto.hex(dk.crypto.random(32))))
	end
	return 0
end

return { run = run }
