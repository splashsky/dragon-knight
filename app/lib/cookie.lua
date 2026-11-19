-- cookie.lua :: Set-Cookie helpers. Headers are queued on req.out_headers and merged
-- into whatever response the handler returns (see main.lua).
local cookie = {}

-- opts: max_age (seconds; nil = session cookie), httponly (default true),
--       samesite (default "Lax"), path (default "/").
function cookie.set(req, name, value, opts)
	opts = opts or {}
	local parts = { name .. "=" .. value, "Path=" .. (opts.path or "/") }
	if opts.max_age then parts[#parts + 1] = "Max-Age=" .. math.tointeger(opts.max_age) end
	if opts.httponly ~= false then parts[#parts + 1] = "HttpOnly" end
	parts[#parts + 1] = "SameSite=" .. (opts.samesite or "Lax")
	if dk.config.cookie_secure then parts[#parts + 1] = "Secure" end
	req.out_headers = req.out_headers or {}
	table.insert(req.out_headers, { "Set-Cookie", table.concat(parts, "; ") })
end

function cookie.clear(req, name)
	cookie.set(req, name, "", { max_age = 0 })
end

return cookie
