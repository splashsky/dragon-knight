-- Unit tests for app/lib/php.lua (run by tests/run.sh through tests/lua/runner.lua).
local php = require("lib.php")
local T = {}

function T.rand_inclusive_truncating_and_swapping()
  local seen = {}
  for _ = 1, 2000 do
    local v = php.rand(5.9, 1.2)          -- -> rand(1, 5)
    assert(math.type(v) == "integer" and v >= 1 and v <= 5, v)
    seen[v] = true
  end
  for i = 1, 5 do assert(seen[i], "never produced " .. i) end
  assert(php.rand(3, 3) == 3)
  assert(php.rand(-2.7, -2.1) == -2)
end

function T.intval_truncates_toward_zero()
  assert(php.intval(2.9) == 2 and php.intval(-2.9) == -2)
  assert(php.intval("12abc") == 12 and php.intval("abc") == 0 and php.intval(nil) == 0)
end

function T.round_and_mysql_int()
  assert(php.round(2.5) == 3 and php.round(-2.5) == -3 and php.round(2.4) == 2)
  assert(php.mysql_int(12.5) == 13 and php.mysql_int(7) == 7)
  assert(php.mysql_uint(-3.2) == 0)
end

function T.number_format()
  assert(php.number_format(0) == "0")
  assert(php.number_format(1234567) == "1,234,567")
  assert(php.number_format(999.5) == "1,000")
  assert(php.number_format(-1234) == "-1,234")
end

function T.str_matches_php_number_printing()
  assert(php.str(1.0) == "1" and php.str(1.2) == "1.2" and php.str(15) == "15")
end

function T.prettydate()
  local ts = os.time({ year = 2004, month = 1, day = 1, hour = 12 })
  assert(php.prettydate(ts) == "January 1, 2004", php.prettydate(ts))
end

function T.nl2br()
  assert(php.nl2br("a\nb") == "a<br />\nb")
  assert(php.nl2br("a\r\nb") == "a<br />\r\nb")
  assert(php.nl2br("a\n\nb") == "a<br />\n<br />\nb")
end

function T.explode_and_lists()
  local t = php.explode(",", "1,2,,3")
  assert(#t == 4 and t[3] == "")
  assert(#php.explode(",", "") == 1)
  assert(php.in_list("0,1,3", 3) and php.in_list("0,1,3", "1") and not php.in_list("0,1,3", 2))
  assert(not php.in_list("2,29.30", 29) and not php.in_list("2,29.30", 30))   -- town 3 typo
  assert(php.implode(",", { 1, "2", 3.0 }) == "1,2,3")
end

function T.is_email()
  assert(php.is_email("a.b+c@example.co.uk"))
  for _, bad in ipairs({ "", "x", "a@b", "a@@b.com", "a b@c.com", "a@-b.com", ".a@b.com", "a@b.c0m" }) do
    assert(not php.is_email(bad), bad)
  end
end

return T
