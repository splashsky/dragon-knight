-- router.lua :: method + path routing.
--
--   local r = router.new()
--   r:get("/shop", auth.game, handler)                -- guards run left to right
--   r:post("/shop/buy/#id", auth.game, handler)       -- #id: digits only, integer param
--   r:get("/character/:name", handler)                -- :name: any one path segment
--   r:route({"GET", "POST"}, "/login", handler)
--
-- A guard is function(req) -> nil (continue) or a response (stop).
-- A handler is function(req, params) -> response table or HTML string; params are
-- also available as req.params. HEAD is routed like GET (main.lua then rolls back
-- the request's writes, so HEAD never changes state).
local router = {}
router.__index = router

function router.new()
	return setmetatable({ routes = {}, exact = {} }, router)
end

local function compile(pattern)
	if not pattern:find("[:#]") then return nil end
	local names, parts = {}, { "^" }
	for seg in pattern:gmatch("/([^/]*)") do
		local kind, name = seg:match("^([:#])([%w_]+)$")
		if kind == ":" then
			parts[#parts + 1] = "/([^/]+)"
			names[#names + 1] = { name = name, int = false }
		elseif kind == "#" then
			parts[#parts + 1] = "/(%d+)"
			names[#names + 1] = { name = name, int = true }
		else
			assert(not seg:find("[:#]"), "bad route segment: " .. seg)
			parts[#parts + 1] = "/" .. seg:gsub("%p", "%%%0")
		end
	end
	parts[#parts + 1] = "$"
	return table.concat(parts), names
end

function router:route(methods, pattern, ...)
	if type(methods) == "string" then methods = { methods } end
	local fns = table.pack(...)
	assert(fns.n >= 1, "route needs a handler")
	local handler = fns[fns.n]
	local guards = {}
	for i = 1, fns.n - 1 do
		assert(type(fns[i]) == "function", "guard must be a function: " .. pattern)
		guards[#guards + 1] = fns[i]
	end
	assert(type(handler) == "function", "handler must be a function: " .. pattern)
	local lpat, names = compile(pattern)
	for _, m in ipairs(methods) do
		local rt = { method = m:upper(), pattern = pattern, lpat = lpat, names = names,
								 guards = guards, handler = handler }
		if lpat then
			self.routes[#self.routes + 1] = rt
		else
			self.exact[pattern] = self.exact[pattern] or {}
			self.exact[pattern][rt.method] = rt
		end
	end
	return self
end

function router:get(pattern, ...) return self:route("GET", pattern, ...) end
function router:post(pattern, ...) return self:route("POST", pattern, ...) end

-- Returns route, params  |  nil, "405", allowed_methods_string  |  nil, "404"
function router:match(method, path)
	if method == "HEAD" then method = "GET" end
	if #path > 1 and path:sub(-1) == "/" then path = path:sub(1, -2) end
	local allowed = {}
	local ex = self.exact[path]
	if ex then
		if ex[method] then return ex[method], {} end
		for m in pairs(ex) do allowed[#allowed + 1] = m end
	end
	for _, rt in ipairs(self.routes) do
		local caps = table.pack(path:match(rt.lpat))
		if caps[1] then
			if rt.method == method then
				local params = {}
				for i, n in ipairs(rt.names) do
					params[n.name] = n.int and (math.tointeger(tonumber(caps[i])) or -1) or caps[i]
				end
				return rt, params
			end
			allowed[#allowed + 1] = rt.method
		end
	end
	if #allowed > 0 then
		table.sort(allowed)
		for i, m in ipairs(allowed) do if m == "GET" then allowed[i] = "GET, HEAD" end end
		return nil, "405", table.concat(allowed, ", ")
	end
	return nil, "404"
end

-- Runs guards then the handler. Returns the response (table or string).
function router.run(rt, req, params)
	req.params = params
	for _, g in ipairs(rt.guards) do
		local res = g(req)
		if res ~= nil then return res end
	end
	return rt.handler(req, params)
end

return router
