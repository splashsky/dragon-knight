-- Unit tests for the World Map's sky as facts (lib/mapsky.lua): built from the weather at
-- pinned times (each weather cell's sky and ground at its centre, the storms, the time of day,
-- the sun by day and the moon by night), the same all through a tick; kept once by the
-- server's tick (lib/tick.lua) in one row of meta, which both renderings read (the SVG
-- overlay, town/sky.lua, and the data, mapsky.json); a read in another tick computes the
-- facts without writing; the row's text round trip; and what building and reading cost.
local clock = require("lib.clock")
local mapsky = require("lib.mapsky")
local sky = require("town.sky")
local tick = require("lib.tick")
local weather = require("lib.weather")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local STORMY = 4000042300   -- day, a great storm and a squall, thunderstorms
local NIGHT = 4000045000

local function with_db(fn)
	dk.db:exec("SAVEPOINT test_mapsky")
	local publish = dk.publish
	dk.publish = function() end
	local ok, err = pcall(fn)
	dk.publish = publish
	dk.db:exec("ROLLBACK TO test_mapsky")
	dk.db:exec("RELEASE test_mapsky")
	if not ok then error(err, 0) end
end

local function row() return dk.db:value("SELECT value FROM meta WHERE key = ?", mapsky.KEY) end

function T.the_facts_are_the_weathers()
	local f = mapsky.build(STORMY)
	eq(f.tick, clock.tick(STORMY), "its tick")
	eq(f.phase, "day")
	eq(#f.cells, mapsky.SIDE * mapsky.SIDE, "a character per weather cell")
	eq(mapsky.SIDE, 51)
	local seen = {}
	for r = 0, mapsky.SIDE - 1 do
		for c = 0, mapsky.SIDE - 1 do
			local lat, lon = (25 - r) * 10 + 5, (c - 25) * 10 + 5
			local w = weather.at(lat, lon, STORMY)
			eq(mapsky.sky(f, r, c), w.sky, ("the sky at %d,%d"):format(lat, lon))
			local code = mapsky.ALPHABET:find(f.cells:sub(r * 51 + c + 1, r * 51 + c + 1), 1, true) - 1
			eq(mapsky.GROUNDS[code % 5 + 1], w.ground, ("the ground at %d,%d"):format(lat, lon))
			seen[w.sky] = true
		end
	end
	assert(seen.thunderstorm and seen.rain and seen.overcast, "a stormy sky sampled")
	local storms = weather.storms(STORMY)
	eq(#f.storms, #storms, "the storms")
	for k, s in ipairs(storms) do
		eq(f.storms[k].born, s.born); eq(f.storms[k].size, s.size)
		eq(f.storms[k].lat, s.lat); eq(f.storms[k].lon, s.lon); eq(f.storms[k].radius, s.radius)
	end
	-- the sun up by day and down at night, the moon then
	assert(f.sun[2] > 0.5, "the sun high by day: " .. f.sun[2])
	local n = mapsky.build(NIGHT)
	eq(n.phase, "night")
	assert(n.sun[2] < 0 and n.moon[2] > 0, "the moon at night")
	assert(mapsky.build(4000000000 - 4000000000 % clock.DAY + 450).sun[2] < 0.3, "the sun low at dawn")
	-- the same all through a tick
	local a = STORMY - STORMY % 10
	eq(mapsky.encode(mapsky.build(a)), mapsky.encode(mapsky.build(a + 9)), "the same all through a tick")
	assert(mapsky.encode(mapsky.build(a)) ~= mapsky.encode(mapsky.build(a + 10)), "the storms move every tick")
end

function T.the_rows_text_round_trips()
	for _, now in ipairs({ STORMY, NIGHT, 4000000000 }) do
		local f = mapsky.build(now)
		local text = mapsky.encode(f)
		eq(text:match("^(%d+)\n"), tostring(f.tick), "keyed by its tick")
		eq(mapsky.encode(mapsky.decode(text)), text, "the round trip")
		local g = mapsky.decode(text)
		for k, s in ipairs(f.storms) do eq(g.storms[k].lat, s.lat, "numbers exactly") end
		eq(g.sun[2], f.sun[2])
	end
end

function T.the_tick_keeps_it_and_both_routes_read_it()
	with_db(function()
		dk.db:exec("DELETE FROM meta WHERE key = ?", mapsky.KEY)
		tick.run(STORMY)
		local text = row()
		assert(text, "the tick wrote the row")
		eq(text, mapsky.encode(mapsky.build(STORMY)), "the tick's facts")
		-- the readers take the row: a doctored one shows (all clear, no storms)
		local f = mapsky.decode(text)
		f.cells = ("0"):rep(#f.cells)
		f.storms = {}
		dk.db:exec("UPDATE meta SET value = ? WHERE key = ?", mapsky.encode(f), mapsky.KEY)
		local svg = sky.markup(STORMY + 5)
		assert(not svg:find("class=\"sky-overcast\"", 1, true) and not svg:find("class=\"sky-storm ", 1, true), "the SVG from the row")
		assert(svg:find("data-sky=\"" .. f.tick .. "\"", 1, true))
		local data = mapsky.json(mapsky.at(STORMY + 5))
		assert(data:find("\"cells\":\"" .. f.cells .. "\"", 1, true) and data:find("\"storms\":[]", 1, true), "the data from the row")
		-- another tick: computed, nothing written
		local before = row()
		local later = mapsky.at(STORMY + 10)
		eq(later.tick, clock.tick(STORMY + 10))
		eq(mapsky.encode(later), mapsky.encode(mapsky.build(STORMY + 10)), "a miss computes")
		eq(row(), before, "a miss writes nothing")
		assert(sky.markup(STORMY + 10):find("class=\"sky-storm ", 1, true), "the SVG computed too")
		-- the next tick replaces it
		tick.run(STORMY + 10)
		eq(row():match("^(%d+)\n"), tostring(clock.tick(STORMY + 10)), "one row, the latest tick's")
		eq(dk.db:value("SELECT count(*) FROM meta WHERE key = ?", mapsky.KEY), 1)
	end)
end

function T.the_data_for_the_webgl_sky()
	local f = mapsky.build(STORMY)
	local data = mapsky.json(f)
	assert(data:find("\"tick\":" .. f.tick, 1, true) and data:find("\"phase\":\"day\"", 1, true), data:sub(1, 80))
	assert(data:find("\"side\":51", 1, true) and data:find("\"cells\":\"" .. f.cells .. "\"", 1, true), "the cells")
	local s = f.storms[1]
	local x = math.floor((s.lon / 5 + 50.5) * 1000 + 0.5) / 1000
	assert(data:find("\"id\":" .. s.born, 1, true) and data:find("\"x\":" .. tostring(x):gsub("%.0$", ""), 1, true),
		"a storm in the map's units")
	assert(#data < 4 * 1024, "small: " .. #data .. " bytes")
end

function T.what_it_costs()
	local n, t0 = 10, os.clock()
	for k = 1, n do mapsky.build(STORMY + k * 10) end
	local build = (os.clock() - t0) / n * 1000
	local text = mapsky.encode(mapsky.build(STORMY))
	t0 = os.clock()
	for _ = 1, 50 do sky.draw(mapsky.decode(text)) end
	local svg = (os.clock() - t0) / 50 * 1000
	t0 = os.clock()
	for _ = 1, 50 do mapsky.json(mapsky.decode(text)) end
	local data = (os.clock() - t0) / 50 * 1000
	-- (budgets about 20 times the optimized build's: also met by `make DEBUG=1`'s sanitizers,
	-- still far below what a real slowdown would cost)
	assert(build < 100 and svg < 50 and data < 5, ("costs: build %.1f, svg %.1f, data %.2f ms"):format(build, svg, data))
	print(("mapsky: built in %.1f ms (once a tick); from the row, the SVG overlay %.1f ms, the data %.2f ms; %d bytes")
		:format(build, svg, data, #text))
end

return T
