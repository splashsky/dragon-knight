-- install.lua :: `dk install` -- create the schema, load the default game data and
-- create the administrator account (port of legacy install.php).
local auth = require("lib.auth")
local mail = require("lib.mail")
local php = require("lib.php")

local USAGE = [[
usage: dk install [--partial] [--force]
                  [--admin <username> <email> <password>] [--charname NAME]
                  [--class 1|2|3] [--difficulty 1|2|3]

  --partial     create tables but load no game data except the control row and the
                first news post (legacy "Partial Setup")
  --force       drop existing Dragon Knight tables first (DESTROYS ALL DATA)
  --admin       administrator account; prompted for when omitted
  --charname    administrator character name (default: the username)
  --class       character class (default 1)
  --difficulty  difficulty (default 1)
]]

-- sessions first: it references users
local TABLES = { "sessions", "babble", "control", "drops", "forum", "items", "levels",
                 "monsters", "news", "spells", "towns", "users" }

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then error("cannot read " .. tostring(err), 0) end
  local s = f:read("a")
  f:close()
  return s
end

local function parse_args(argv)
  local o = { class = "1", difficulty = "1" }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--partial" then o.partial = true
    elseif a == "--force" then o.force = true
    elseif a == "--admin" then
      o.username, o.email, o.password = argv[i + 1], argv[i + 2], argv[i + 3]
      if not o.password then return nil, "--admin needs <username> <email> <password>" end
      i = i + 3
    elseif a == "--charname" or a == "--class" or a == "--difficulty" then
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
  for _, k in ipairs({ "class", "difficulty" }) do
    local n = math.tointeger(tonumber(o[k]))
    if not n or n < 1 or n > 3 then errs[#errs + 1] = k .. " must be 1, 2 or 3" end
    o[k] = n
  end
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

-- seed.sql has one INSERT per line; partial setup keeps only control + news
-- (legacy populated those two even for "Partial Setup").
local function seed_sql(full, sql)
  if full then return sql end
  local keep = {}
  for line in sql:gmatch("[^\n]+") do
    if line:find("^INSERT INTO control ") or line:find("^INSERT INTO news ") then
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

  local now = dk.now()
  -- legacy install never set difficulty (left 0, which has no name/modifier); default 1 here
  local _, id = dk.db:exec(
    "INSERT INTO users (username, password, email, verify, charname, charclass, difficulty, " ..
    "regdate, onlinetime, authlevel) VALUES (?, ?, ?, '1', ?, ?, ?, ?, ?, 1)",
    o.username, auth.hash_password(o.password), o.email, o.charname, o.class, o.difficulty, now, now)

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
