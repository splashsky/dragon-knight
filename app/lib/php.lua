-- php.lua :: PHP-compatible helpers so game mechanics match legacy/ exactly.
-- See PLAN.md "Mechanics fidelity" and docs/APP.md.
local php = {}

local floor, ceil, mtype = math.floor, math.ceil, math.type

-- (int) cast: truncate toward zero. Strings use their leading numeric prefix ("12abc" -> 12).
function php.intval(v)
  if type(v) == "string" then
    return math.tointeger(tonumber(v:match("^%s*([+-]?%d+)") or "0")) or 0
  elseif type(v) == "boolean" then
    return v and 1 or 0
  elseif type(v) ~= "number" then
    return 0
  end
  if v ~= v or v == math.huge or v == -math.huge then return 0 end
  local i = v >= 0 and floor(v) or ceil(v)
  return math.tointeger(i) or 0
end

-- PHP rand(min, max): args cast to int (truncation), swapped when min > max, inclusive.
function php.rand(min, max)
  local a, b = php.intval(min), php.intval(max)
  if a > b then a, b = b, a end
  return math.random(a, b)
end

-- ceil()/floor(), returning Lua integers when representable (PHP returns floats, but
-- they print identically).
function php.ceil(x) return ceil(x) end
function php.floor(x) return floor(x) end

-- PHP round($x): half away from zero, to an integer.
function php.round(x)
  local v = x >= 0 and floor(x + 0.5) or ceil(x - 0.5)
  return math.tointeger(v) or v
end

-- What MySQL stored when PHP wrote a float into an integer column: round half away
-- from zero. php.mysql_uint also clamps negatives to 0 (UNSIGNED columns, non-strict mode).
function php.mysql_int(x)
  if type(x) ~= "number" then x = tonumber(x) or 0 end
  return math.tointeger(x) or php.round(x)
end

function php.mysql_uint(x)
  local v = php.mysql_int(x)
  return v < 0 and 0 or v
end

-- PHP string conversion of a number: 1.0 -> "1", 1.2 -> "1.2" (precision 14).
function php.str(v)
  if mtype(v) == "float" then
    if v == floor(v) and v > -1e15 and v < 1e15 then return string.format("%d", v) end
    return (string.format("%.14G", v))
  end
  if v == nil then return "" end
  return tostring(v)
end

-- number_format($n): rounds to an integer, "," as the thousands separator.
function php.number_format(n)
  local s = string.format("%d", php.round(tonumber(n) or 0))
  local sign, digits = s:match("^(-?)(%d+)$")
  digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  if digits == "0" then sign = "" end
  return sign .. digits
end

-- nl2br() WITHOUT escaping (PHP semantics). Templates should use h.nl2br, which escapes.
function php.nl2br(s)
  s = tostring(s or "")
  return (s:gsub("([\r\n])([\r\n]?)", function(a, b)
    if b == "" then return "<br />" .. a end
    if a ~= b then return "<br />" .. a .. b end
    return "<br />" .. a .. "<br />" .. b
  end))
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
                 "August", "September", "October", "November", "December" }

-- date("F j, Y", ts) in server local time (like PHP date()).
function php.prettydate(ts)
  local t = os.date("*t", tonumber(ts) or 0)
  return string.format("%s %d, %d", MONTHS[t.month], t.day, t.year)
end

-- date("Y-m-d H:i:s", ts): the MySQL DATETIME text the legacy pages printed raw.
function php.datetime(ts)
  return os.date("%Y-%m-%d %H:%M:%S", tonumber(ts) or 0)
end

-- explode(sep, s): plain split, keeps empty fields. explode(",", "") == { "" }.
function php.explode(sep, s)
  s = tostring(s or "")
  local out, i = {}, 1
  while true do
    local a, b = s:find(sep, i, true)
    if not a then
      out[#out + 1] = s:sub(i)
      return out
    end
    out[#out + 1] = s:sub(i, a - 1)
    i = b + 1
  end
end

function php.implode(sep, t)
  local parts = {}
  for i = 1, #t do parts[i] = php.str(t[i]) end
  return table.concat(parts, sep)
end

-- Loose == between scalars, as PHP 4/5 did for the values this game compares
-- (numeric strings compare as numbers: "3" == 3, "29.30" ~= 29).
function php.loose_eq(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return na == nb end
  return tostring(a) == tostring(b)
end

-- in_array($v, explode(",", $list)) for comma-list columns (users.spells, users.towns,
-- towns.itemslist).
function php.in_list(list, v)
  for _, item in ipairs(php.explode(",", list)) do
    if php.loose_eq(item, v) then return true end
  end
  return false
end

-- Modern, sane email check (the legacy regex hard-coded a 2006 TLD list).
function php.is_email(s)
  if type(s) ~= "string" or #s > 254 then return false end
  local localpart, domain = s:match("^([%w%.!#%$%%&'%*%+/=%?%^_`{|}~%-]+)@([%w%.%-]+)$")
  if not localpart or #localpart > 64 then return false end
  if localpart:sub(1, 1) == "." or localpart:sub(-1) == "." or localpart:find("..", 1, true) then
    return false
  end
  local labels = php.explode(".", domain)
  if #labels < 2 then return false end
  for _, l in ipairs(labels) do
    if #l == 0 or #l > 63 or l:sub(1, 1) == "-" or l:sub(-1) == "-" then return false end
  end
  return labels[#labels]:find("^%a%a+$") ~= nil
end

-- trim() of whitespace PHP strips by default (" \t\n\r\0\x0B").
function php.trim(s)
  return (tostring(s or ""):gsub("^[ \t\n\r%z\v]+", ""):gsub("[ \t\n\r%z\v]+$", ""))
end

return php
