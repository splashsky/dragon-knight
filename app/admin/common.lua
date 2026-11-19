-- admin/common.lua :: shared pieces of the control panel (port of legacy admin.php header
-- and admindisplay()).
local auth = require("lib.auth")
local php = require("lib.php")
local view = require("lib.view")

local common = {}

common.LAYOUT = { layout = "admin", nav = false }

-- Guard: legacy admin.php died with a message when logged out, and with the privileges
-- message for authlevel ~= 1. The game's open/closed switch does not apply here.
function common.guard(req)
  if not req.user then
    return view.message(req, "Error",
      'Please log in to the <a href="/login">game</a> before using the control panel.',
      { nav = false, status = 403 })
  end
  return auth.admin(req)
end

-- Renders templates/<template>.html inside the admin layout (legacy admindisplay()).
function common.page(req, title, template, ctx, status)
  return view.page(req, title, template, ctx,
                   { layout = "admin", nav = false, status = status })
end

-- Trusted-HTML message page in the admin layout.
function common.message(req, title, html, status)
  return view.message(req, title, html, { layout = "admin", nav = false, status = status })
end

function common.not_found(req, what)
  return view.error(req, 404, "Not Found", "No such " .. what .. ".",
                    { layout = "admin", nav = false })
end

-- Raw form value as a string ("" when absent, like PHP extract() of a missing key).
function common.field(req, name)
  local v = req.form[name]
  if type(v) ~= "string" then return "" end
  return v
end

-- PHP is_numeric(): optional leading whitespace, sign, decimal digits with an optional
-- fraction and exponent. (PHP 4/5 also took hex like "0x1A"; we don't.)
function common.is_numeric(s)
  if type(s) == "number" then return true end
  if type(s) ~= "string" then return false end
  local body = s:match("^[ \t\n\r\v\f]*([+-]?.*)$")
  local mant, exp = body:match("^[+-]?([%d%.]+)(.*)$")
  if not mant then return false end
  if not (mant:find("^%d+%.?%d*$") or mant:find("^%.%d+$")) then return false end
  return exp == "" or exp:find("^[eE][+-]?%d+$") ~= nil
end

local INT_LIMIT = 9007199254740991   -- 2^53 - 1: beyond this a float can't hold an exact int

-- What MySQL stored when legacy wrote a numeric string into an integer column
-- (rounded; clamped to a sane range).
function common.to_int(s)
  local n = tonumber(s) or 0
  if n ~= n then return 0 end
  if n > INT_LIMIT then n = INT_LIMIT elseif n < -INT_LIMIT then n = -INT_LIMIT end
  return php.mysql_int(n)
end

function common.to_real(s)
  local n = tonumber(s) or 0
  if n ~= n or n == math.huge or n == -math.huge then return 0.0 end
  return n + 0.0
end

-- Display a DB value in a form field (REAL columns print like PHP: 1.0 -> "1").
function common.str(v)
  return php.str(v)
end

return common
