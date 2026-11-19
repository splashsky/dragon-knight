-- Unit tests for app/lib/router.lua.
local router = require("lib.router")
local T = {}

local function h(name) return function() return name end end

function T.matches_exact_params_and_methods()
  local r = router.new()
  r:get("/", h("home"))
  r:get("/shop/buy/#id", h("confirm"))
  r:post("/shop/buy/#id", h("buy"))
  r:get("/u/:name", h("user"))
  local rt, p = r:match("GET", "/shop/buy/12")
  assert(rt and router.run(rt, {}, p) == "confirm" and p.id == 12 and math.type(p.id) == "integer")
  rt, p = r:match("POST", "/shop/buy/12/")
  assert(rt and router.run(rt, {}, p) == "buy")
  rt, p = r:match("HEAD", "/u/bob")
  assert(rt and p.name == "bob")
  assert(r:match("GET", "/"))
end

function T.not_found_and_method_not_allowed()
  local r = router.new()
  r:get("/a", h("a"))
  r:post("/b/#id", h("b"))
  local rt, why, allowed = r:match("POST", "/a")
  assert(not rt and why == "405" and allowed == "GET, HEAD", allowed)
  rt, why, allowed = r:match("GET", "/b/3")
  assert(not rt and why == "405" and allowed == "POST")
  rt, why = r:match("GET", "/b/x")
  assert(not rt and why == "404")
  rt, why = r:match("GET", "/nope")
  assert(not rt and why == "404")
end

function T.guards_short_circuit()
  local r = router.new()
  local order = {}
  r:get("/g", function() order[#order + 1] = "g1" end,
              function() order[#order + 1] = "g2"; return "stopped" end,
              function() order[#order + 1] = "handler"; return "ran" end)
  local rt, p = r:match("GET", "/g")
  assert(router.run(rt, {}, p) == "stopped" and #order == 2)
end

return T
