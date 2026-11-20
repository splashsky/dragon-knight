-- wire.lua :: regions and the live wire format (docs/APP.md "Live client").
--
-- Regions. A template marks a part of the page that changes on its own:
--   {{{ region("left") }}}<aside class="dk-left" data-r="left">...</aside>{{{ endregion() }}}
-- region()/endregion() (view.lua helpers) leave markers in the rendered string: "<\1name>"
-- and "</\1>". Escaped text never contains "<", so user data can't forge them. Regions
-- nest; names are unique in a page; "root" is the <body>, "head" the <head> contents
-- (without <title>: compared, never sent). wire.split parses the markers in one pass and
-- hashes each region's skeleton: its HTML with every child region replaced by "<\1name>",
-- so a region's hash changes only when its own markup does.
--
-- The wire format (application/x-dk-live): "DK1\n", then frames
--   <op> [<arg> ...] <length>\n<length bytes of payload>\n
-- (lengths in bytes, payloads raw). Ops: title, url, events <kind>, region <name>, hashes,
-- go, doc. Clients skip ops they don't know.
local wire = {}

wire.CONTENT_TYPE = "application/x-dk-live; charset=utf-8"
wire.MAGIC = "DK1\n"
wire.HASH_HEX = 12
wire.MAX_HOPS = 5

-- the placeholder for <html>'s data-h attribute (view.lua's hashes() helper)
wire.HASHES = "\1H"

local NAME = "^[a-z][a-z0-9-]*$"

function wire.valid_name(name)
	return type(name) == "string" and #name <= 32 and name:find(NAME) ~= nil
end

function wire.open(name)
	assert(wire.valid_name(name), "region: bad name " .. tostring(name))
	return "<\1" .. name .. ">"
end

wire.CLOSE = "</\1>"

-- The page without markers (and without the data-h placeholder).
function wire.strip(html)
	return (html:gsub("</?\1[%w%-]*>", ""):gsub("\1H", ""))
end

local function build(node, skeleton, out)
	for _, p in ipairs(node.parts) do
		if type(p) == "string" then out[#out + 1] = p
		elseif skeleton then out[#out + 1] = "<\1" .. p.name .. ">"
		else build(p, false, out) end
	end
	return out
end

-- A region's HTML (its children's included, markers gone).
function wire.html(node)
	return table.concat(build(node, false, {}))
end

-- Splits a page at its markers: the document node { parts, children, regions = { name =
-- node }, order = { node, ... } }; each region node { name, parts, children, hash }.
-- Raises on unbalanced markers or a repeated name.
function wire.split(html)
	local doc = { parts = {}, children = {}, regions = {}, order = {} }
	local stack, pos = { doc }, 1
	while true do
		local s, e, close, name = html:find("<(/?)\1([%w%-]*)>", pos)
		if not s then break end
		local top = stack[#stack]
		if s > pos then top.parts[#top.parts + 1] = html:sub(pos, s - 1) end
		if close == "" then
			if doc.regions[name] then error("region " .. name .. " appears twice", 0) end
			local node = { name = name, parts = {}, children = {} }
			top.parts[#top.parts + 1] = node
			top.children[#top.children + 1] = node
			doc.regions[name] = node
			doc.order[#doc.order + 1] = node
			stack[#stack + 1] = node
		else
			if #stack == 1 then error("endregion() without region()", 0) end
			stack[#stack] = nil
		end
		pos = e + 1
	end
	if #stack > 1 then error("region " .. stack[#stack].name .. " is not closed", 0) end
	doc.parts[#doc.parts + 1] = html:sub(pos)
	for _, node in ipairs(doc.order) do
		node.hash = dk.crypto.hex(dk.crypto.sha256(table.concat(build(node, true, {})))):sub(1, wire.HASH_HEX)
	end
	return doc
end

-- "name=hash ..." of every region, in page order; with `have` (the client's), only those
-- that differ, and "name=-" for the client's regions the page no longer has (the client
-- merges them into what it has).
function wire.hashes(doc, have)
	local out = {}
	for _, node in ipairs(doc.order) do
		if not have or have[node.name] ~= node.hash then out[#out + 1] = node.name .. "=" .. node.hash end
	end
	if have then
		local gone = {}
		for name in pairs(have) do
			if not doc.regions[name] then gone[#gone + 1] = name .. "=-" end
		end
		table.sort(gone)
		for _, g in ipairs(gone) do out[#out + 1] = g end
	end
	return table.concat(out, " ")
end

-- A full page: markers gone, every region's hash on <html data-h="...">. A page whose
-- markers don't balance is a template bug: an error in dev, else the page without hashes.
function wire.page(html)
	local ok, doc = pcall(wire.split, html)
	if not ok then
		if dk.config.dev then error("regions: " .. doc) end
		dk.log("error", "regions: " .. doc)
		return wire.strip(html)
	end
	local out = wire.html(doc)
	local at = out:find(wire.HASHES, 1, true)
	if not at then return out end
	return out:sub(1, at - 1) .. ' data-h="' .. wire.hashes(doc) .. '"' .. out:sub(at + #wire.HASHES)
end

-- The regions the client must get: walking from `root`, a region whose hash the client
-- has is skipped and its children compared; any other is sent whole.
function wire.changed(doc, have)
	local out = {}
	local function visit(node)
		if have[node.name] == node.hash then
			for _, c in ipairs(node.children) do visit(c) end
		else
			out[#out + 1] = node
		end
	end
	if doc.regions.root then visit(doc.regions.root) end
	return out
end

-- X-DK-Have: "name=hash name=hash ..." -> { name = hash } (at most 64; junk ignored)
function wire.parse_have(s)
	local have, n = {}, 0
	for name, hash in tostring(s or ""):gmatch("([a-z][a-z0-9-]*)=(%x+)") do
		n = n + 1
		if n > 64 then break end
		have[name] = hash
	end
	return have
end

function wire.frame(op, args, payload)
	payload = payload or ""
	local head = op
	if args and args ~= "" then head = head .. " " .. args end
	return head .. " " .. #payload .. "\n" .. payload .. "\n"
end

-- frames: { { op, args, payload }, ... } -> the body
function wire.encode(frames)
	local out = { wire.MAGIC }
	for _, f in ipairs(frames) do out[#out + 1] = wire.frame(f[1], f[2], f[3]) end
	return table.concat(out)
end

-- The body -> { { op = "region", args = { "left" }, payload = "..." }, ... } (tests and
-- tools; raises on a malformed body).
function wire.decode(body)
	assert(body:sub(1, #wire.MAGIC) == wire.MAGIC, "wire: no DK1 header")
	local frames, pos = {}, #wire.MAGIC + 1
	while pos <= #body do
		local nl = assert(body:find("\n", pos, true), "wire: no frame line")
		local words = {}
		for w in body:sub(pos, nl - 1):gmatch("%S+") do words[#words + 1] = w end
		local len = assert(math.tointeger(tonumber(table.remove(words))), "wire: no length")
		local op = assert(table.remove(words, 1), "wire: no op")
		local payload = body:sub(nl + 1, nl + len)
		assert(#payload == len and body:sub(nl + len + 1, nl + len + 1) == "\n", "wire: short frame")
		frames[#frames + 1] = { op = op, args = words, payload = payload }
		pos = nl + len + 2
	end
	return frames
end

-- "a=1&b=x+y" -> { a = "1", b = "x y" } (the last of a repeated key wins, like the engine's)
function wire.parse_query(qs)
	local out = {}
	for pair in tostring(qs or ""):gmatch("[^&]+") do
		local k, v = pair:match("^([^=]*)=?(.*)$")
		k = dk.urldecode((k:gsub("%+", " ")))
		if k ~= "" then out[k] = dk.urldecode((v:gsub("%+", " "))) end
	end
	return out
end

-- The cookies a request sees after the Set-Cookie headers queued so far (an internal
-- redirect after a login or logout sees the new session).
function wire.cookies_after(cookies, out_headers)
	local c = {}
	for k, v in pairs(cookies or {}) do c[k] = v end
	for _, hd in ipairs(out_headers or {}) do
		if hd[1]:lower() == "set-cookie" then
			local name, value = hd[2]:match("^([^=;%s]+)=([^;]*)")
			if name then
				if hd[2]:find("[Mm]ax%-[Aa]ge=0") then c[name] = nil else c[name] = value end
			end
		end
	end
	return c
end

return wire
