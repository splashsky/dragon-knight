-- json.lua :: a small JSON encoder, for event data (dk.publish(channel, event,
-- json.encode(t))) and other JSON answers.
--
--   json.encode(v) -> string
--     nil, json.null          null
--     booleans, numbers       true/false; integers as they are, floats shortest exact
--                             (NaN and infinities are errors)
--     strings                 escaped; invalid UTF-8 bytes become U+FFFD; < > & U+2028
--                             U+2029 are \u-escaped too, so the text is also safe inside
--                             an HTML <script> element
--     tables                  an array when the keys are exactly 1..n (or the table is
--                             marked with json.array), else an object with string keys
--                             (sorted, so the output is stable); an empty table is {}
--                             unless marked: json.array({}) is []
--   Errors: other key types, sparse or mixed tables, functions and the like, cycles,
--   nesting deeper than 64.
local json = {}

json.null = setmetatable({}, { __tostring = function() return "null" end })

local array_mt = { __name = "json.array" }

function json.array(t)
	return setmetatable(t or {}, array_mt)
end

local ESCAPES = {
	['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
	["\t"] = "\\t", ["<"] = "\\u003c", [">"] = "\\u003e", ["&"] = "\\u0026",
	["\226\128\168"] = "\\u2028", ["\226\128\169"] = "\\u2029",
}

local function escape_char(c)
	return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
end

local function valid_utf8(s)
	if utf8.len(s) then return s end
	local out, i = {}, 1
	while true do
		local ok, bad = utf8.len(s, i)
		if ok then
			out[#out + 1] = s:sub(i)
			break
		end
		out[#out + 1] = s:sub(i, bad - 1)
		out[#out + 1] = "\239\191\189"
		i = bad + 1
	end
	return table.concat(out)
end

local function encode_string(s)
	s = valid_utf8(s)
	s = s:gsub('[%c"\\<>&]', escape_char):gsub("\226\128[\168\169]", escape_char)
	return '"' .. s .. '"'
end

local function encode_number(n)
	if math.type(n) == "integer" then return tostring(n) end
	if n ~= n or n == math.huge or n == -math.huge then
		error("json.encode: cannot encode " .. tostring(n), 0)
	end
	local s = string.format("%.14g", n)
	if tonumber(s) ~= n then s = string.format("%.17g", n) end
	return s
end

local encode_value

local function encode_table(t, out, seen, depth)
	if seen[t] then error("json.encode: cycle in table", 0) end
	if depth > 64 then error("json.encode: nested too deep", 0) end
	seen[t] = true
	local n, strings, ints = #t, 0, 0
	for k in pairs(t) do
		if math.type(k) == "integer" and k >= 1 and k <= n then
			ints = ints + 1
		elseif math.type(k) == "integer" then
			error("json.encode: sparse array", 0)
		elseif type(k) == "string" then
			strings = strings + 1
		else
			error("json.encode: cannot encode a table key of type " .. (math.type(k) or type(k)), 0)
		end
	end
	if getmetatable(t) == array_mt or (ints > 0 and strings == 0) then
		if strings > 0 then error("json.encode: array with string keys", 0) end
		if ints ~= n then error("json.encode: sparse array", 0) end
		out[#out + 1] = "["
		for i = 1, n do
			if i > 1 then out[#out + 1] = "," end
			encode_value(t[i], out, seen, depth + 1)
		end
		out[#out + 1] = "]"
	else
		if ints > 0 then error("json.encode: table with both array and string keys", 0) end
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys)
		out[#out + 1] = "{"
		for i, k in ipairs(keys) do
			if i > 1 then out[#out + 1] = "," end
			out[#out + 1] = encode_string(k)
			out[#out + 1] = ":"
			encode_value(t[k], out, seen, depth + 1)
		end
		out[#out + 1] = "}"
	end
	seen[t] = nil
end

function encode_value(v, out, seen, depth)
	local tv = type(v)
	if v == nil or v == json.null then
		out[#out + 1] = "null"
	elseif tv == "boolean" then
		out[#out + 1] = v and "true" or "false"
	elseif tv == "number" then
		out[#out + 1] = encode_number(v)
	elseif tv == "string" then
		out[#out + 1] = encode_string(v)
	elseif tv == "table" then
		encode_table(v, out, seen, depth)
	else
		error("json.encode: cannot encode a " .. tv, 0)
	end
end

function json.encode(v)
	local out = {}
	encode_value(v, out, {}, 0)
	return table.concat(out)
end

return json
