-- content/sandbox.lua :: running content code. Content files (app/content/) run in a
-- restricted environment with only safe globals (no dk, require, io, os, debug), and every
-- call into content code (loading a file, a spell's cast, ...) gets an instruction budget,
-- so a runaway loop fails like any other error instead of hanging the request.
local sandbox = {}

-- What content code may use. math has no random/randomseed: dice come from the action
-- context (s:roll), so tests can script them.
sandbox.GLOBALS = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type" }
sandbox.LIBRARIES = { "math", "string", "table" }
local GLOBAL_VALUES = {
	assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall, select = select,
	tonumber = tonumber, tostring = tostring, type = type,
}
local LIBRARY_VALUES = { math = math, string = string, table = table }
local LEFT_OUT = { math = { random = true, randomseed = true } }

-- Instructions one call into content code may run.
sandbox.BUDGET = 10000000

local ALLOWED = table.concat(sandbox.GLOBALS, ", ") .. ", " .. table.concat(sandbox.LIBRARIES, ", ")

-- A fresh environment for one content file: copies of the allowed globals and libraries
-- (a file can't change another's); reading or setting any other global is an error.
function sandbox.env()
	local env = {}
	for name, v in pairs(GLOBAL_VALUES) do env[name] = v end
	for name, lib in pairs(LIBRARY_VALUES) do
		local copy = {}
		for k, v in pairs(lib) do
			if not (LEFT_OUT[name] and LEFT_OUT[name][k]) then copy[k] = v end
		end
		env[name] = copy
	end
	return setmetatable(env, {
		__index = function(_, k)
			error("unknown global '" .. tostring(k) .. "' (content code can use " .. ALLOWED .. ")", 2)
		end,
		__newindex = function(_, k)
			error("content code can't set the global '" .. tostring(k) .. "' (use a local)", 2)
		end,
	})
end

-- Calls fn(...) with the instruction budget. Returns true and fn's results, or false and
-- the error message with a traceback. Once the budget is spent every further instruction
-- fails, so content code can't pcall its way past it.
local function call(fn, ...)
	local function over()
		-- back in this function (the content call is over): let it restore the old hook
		if debug.getinfo(2, "f").func == call then return end
		debug.sethook(over, "", 1)
		error("content code ran too long (more than " .. sandbox.BUDGET .. " instructions)", 2)
	end
	local old = table.pack(debug.gethook())
	debug.sethook(over, "", sandbox.BUDGET)
	local res = table.pack(xpcall(fn, debug.traceback, ...))
	if type(old[1]) == "function" then debug.sethook(old[1], old[2], old[3]) else debug.sethook() end
	return table.unpack(res, 1, res.n)
end
sandbox.call = call

return sandbox
