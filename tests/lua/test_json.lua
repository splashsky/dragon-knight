-- Unit tests for app/lib/json.lua.
local json = require("lib.json")
local T = {}

local function fails(v, needle)
	local ok, err = pcall(json.encode, v)
	assert(not ok, "expected an error")
	assert(tostring(err):find(needle, 1, true), err)
end

function T.scalars()
	assert(json.encode(nil) == "null")
	assert(json.encode(json.null) == "null")
	assert(json.encode(true) == "true" and json.encode(false) == "false")
	assert(json.encode(42) == "42" and json.encode(-7) == "-7")
	assert(json.encode(math.maxinteger) == "9223372036854775807")
	assert(json.encode(1.5) == "1.5")
	assert(json.encode(0.1) == "0.1")
	assert(tonumber(json.encode(1 / 3)) == 1 / 3)
	assert(json.encode(2.0) == "2")
	fails(0 / 0, "cannot encode")
	fails(math.huge, "cannot encode")
	fails(print, "cannot encode a function")
end

function T.strings()
	assert(json.encode("plain") == '"plain"')
	assert(json.encode('a"b\\c') == '"a\\"b\\\\c"')
	assert(json.encode("l1\nl2\r\t\b\f") == '"l1\\nl2\\r\\t\\b\\f"')
	assert(json.encode("\0\1\31\127") == '"\\u0000\\u0001\\u001f\\u007f"')
	-- safe inside HTML: no tag or entity can start
	assert(json.encode("</script><b>&amp;") == '"\\u003c/script\\u003e\\u003cb\\u003e\\u0026amp;"')
	assert(json.encode("a\226\128\168b\226\128\169c") == '"a\\u2028b\\u2029c"')
	-- UTF-8 passes through; invalid bytes become U+FFFD
	assert(json.encode("héllo ✓") == '"héllo ✓"')
	assert(json.encode("a\255b\192") == '"a\239\191\189b\239\191\189"')
	assert(json.encode("\237\160\128") == '"\239\191\189\239\191\189\239\191\189"')  -- a surrogate
end

function T.tables()
	assert(json.encode({ 1, 2, "x" }) == '[1,2,"x"]')
	assert(json.encode({ b = 1, a = { true, json.null }, c = "s" }) == '{"a":[true,null],"b":1,"c":"s"}')
	assert(json.encode({}) == "{}")
	assert(json.encode(json.array({})) == "[]")
	assert(json.encode(json.array({ 1 })) == "[1]")
	assert(json.encode({ id = 3, author = "Al", text = "<hi>", time = 1700000000 }) ==
		'{"author":"Al","id":3,"text":"\\u003chi\\u003e","time":1700000000}')
	fails({ 1, 2, x = 3 }, "both array and string keys")
	fails({ [1] = 1, [3] = 3 }, "sparse array")
	fails({ [2] = 2 }, "sparse array")
	fails({ [1.5] = 1 }, "table key of type float")
	fails({ [true] = 1 }, "table key of type boolean")
	fails(json.array({ 1, x = 2 }), "array with string keys")
	local cyc = {}
	cyc.self = cyc
	fails(cyc, "cycle")
	local deep = {}
	for _ = 1, 70 do deep = { deep } end
	fails(deep, "too deep")
	-- the same table twice (not a cycle) is fine
	local shared = { 1 }
	assert(json.encode({ shared, shared }) == "[[1],[1]]")
end

return T
