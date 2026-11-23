-- tools/weather_fields.lua :: the quantiles of the weather's base-sky fields (lib/weather.lua
-- FIELDS.*.QUANTILES): each field's raw value sampled over the map's weather cells at many
-- times far apart, sorted, and read at the shares 0, 1/64, ..., 1. Run from the project's
-- root with any Lua 5.4 or later (it needs only the pure modules lib/weather.lua loads):
--   lua tools/weather_fields.lua
-- and paste its output over the tables when a field's octaves or wind change.
package.path = "app/?.lua;" .. package.path
local weather = require("lib.weather")

local REACH, TIMES, GAP, START = 25, 600, 3607, 4000000000
for _, kind in ipairs({ "cloud", "fog" }) do
	local values = {}
	for n = 0, TIMES - 1 do
		local t = START + n * GAP
		for y = -REACH, REACH do
			for x = -REACH, REACH do values[#values + 1] = weather.field(kind, x, y, t, true) end
		end
	end
	table.sort(values)
	local out = {}
	for i = 0, 64 do
		local v = values[math.min(#values, math.floor(i / 64 * (#values - 1)) + 1)]
		out[#out + 1] = (("%.5f"):format(v):gsub("0+$", ""))
	end
	-- ten a line, as the module has them
	local lines = {}
	for i = 1, #out, 10 do lines[#lines + 1] = table.concat(out, ", ", i, math.min(i + 9, #out)) end
	print(("FIELDS.%s.QUANTILES = {\n\t%s,\n}"):format(kind, table.concat(lines, ",\n\t")))
end
