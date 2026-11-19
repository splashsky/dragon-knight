-- mail.lua :: "sends" email by writing an .eml file to the outbox directory
-- (dk.config.outbox_dir, default data/outbox) and logging it.
local game = require("lib.game")

local mail = {}

function mail.outbox_dir()
  local d = dk.config.outbox_dir
  if type(d) ~= "string" or d == "" then d = "data/outbox" end
  return d
end

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Creates the outbox directory (and parents) if needed.
function mail.ensure_outbox()
  local dir = mail.outbox_dir()
  local probe = io.open(dir .. "/.probe", "w")
  if probe then
    probe:close()
    os.remove(dir .. "/.probe")
    return true
  end
  return os.execute("mkdir -p " .. shell_quote(dir)) == true
end

local function header_value(s)
  return (tostring(s or ""):gsub("[\r\n]+", " "))
end

-- Returns true on success, false (and logs) on failure.
function mail.send(to, subject, body)
  local control = game.control()
  local from = control.adminemail ~= "" and control.adminemail or "noreply@localhost"
  local text = tostring(body):gsub("\r\n", "\n"):gsub("\n", "\r\n")
  local msg = table.concat({
    "From: " .. header_value(from),
    "To: " .. header_value(to),
    "Subject: " .. header_value(subject),
    "Date: " .. os.date("!%a, %d %b %Y %H:%M:%S +0000"),
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: 8bit",
    "",
    text,
  }, "\r\n")
  local dir = mail.outbox_dir()
  local path = string.format("%s/%d-%s.eml", dir, dk.now(), dk.crypto.hex(dk.crypto.random(6)))
  local f = io.open(path, "wb")
  if not f and mail.ensure_outbox() then f = io.open(path, "wb") end
  if not f then
    dk.log("error", "mail: cannot write " .. path)
    return false
  end
  local ok = f:write(msg)
  f:close()
  if not ok then
    dk.log("error", "mail: write failed for " .. path)
    return false
  end
  dk.log("info", string.format("mail: to=<%s> subject=%q -> %s", header_value(to), header_value(subject), path))
  return true
end

return mail
