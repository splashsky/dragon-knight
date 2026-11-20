-- Unit tests for app/lib/wire.lua (regions and the live wire format).
local wire = require("lib.wire")
local T = {}

local O, C = wire.open, wire.CLOSE

-- <html><head>…</head><body> with a left box (loc inside) and a main
local function page(loc, main, extra)
	return "<!doctype html><html" .. wire.HASHES .. "><head><title>t</title>" .. O("head") .. "<link>" .. C ..
		"</head>" .. O("root") .. "<body>" .. O("left") .. '<aside data-r="left">' .. O("loc") ..
		'<section data-r="loc">' .. loc .. "</section>" .. C .. "</aside>" .. C .. O("main") ..
		'<main data-r="main">' .. main .. "</main>" .. C .. (extra or "") .. "</body>" .. C .. "</html>"
end

local function have_of(doc)
	local h = {}
	for _, n in ipairs(doc.order) do h[n.name] = n.hash end
	return h
end

local function names(list)
	local out = {}
	for _, n in ipairs(list) do out[#out + 1] = n.name end
	return table.concat(out, ",")
end

function T.split_and_html()
	local doc = wire.split(page("1,2", "hello"))
	assert(names(doc.order) == "head,root,left,loc,main")
	assert(wire.html(doc.regions.loc) == '<section data-r="loc">1,2</section>')
	assert(wire.html(doc.regions.left) == '<aside data-r="left"><section data-r="loc">1,2</section></aside>')
	assert(#doc.regions.root.children == 2)
	assert(#doc.regions.head.hash == wire.HASH_HEX)
	assert(not wire.html(doc):find("<\1", 1, true) and not wire.html(doc):find("</\1", 1, true), "no markers left")
end

function T.skeleton_hashes()
	local a, b = wire.split(page("1,2", "x")), wire.split(page("1,3", "x"))
	-- a child's change leaves its parents' hashes alone
	assert(a.regions.loc.hash ~= b.regions.loc.hash)
	assert(a.regions.left.hash == b.regions.left.hash and a.regions.root.hash == b.regions.root.hash)
	assert(a.regions.main.hash == b.regions.main.hash)
	-- a parent's own markup changes its hash only
	local c = wire.split(page("1,2", "x", "<footer>"))
	assert(c.regions.root.hash ~= a.regions.root.hash and c.regions.left.hash == a.regions.left.hash)
end

function T.changed()
	local a, b = wire.split(page("1,2", "x")), wire.split(page("1,3", "y"))
	assert(names(wire.changed(b, have_of(a))) == "loc,main")
	assert(names(wire.changed(a, have_of(a))) == "")
	assert(names(wire.changed(b, {})) == "root", "nothing known: the whole body")
	local c = wire.split(page("1,2", "x", "<footer>"))
	assert(names(wire.changed(c, have_of(a))) == "root", "a changed parent goes whole")
end

function T.hashes()
	local a, b = wire.split(page("1,2", "x")), wire.split(page("1,3", "x"))
	assert(wire.hashes(a):match("^head=%x+ root=%x+ left=%x+ loc=%x+ main=%x+$"))
	local h = have_of(a)
	h.gone = "abc"
	assert(wire.hashes(b, h) == "loc=" .. b.regions.loc.hash .. " gone=-")
	assert(wire.hashes(a, have_of(a)) == "")
end

function T.page()
	local html = wire.page(page("1", "x"))
	assert(not html:find("\1", 1, true))
	assert(html:find('<html data%-h="head=%x+ root=%x+ left=%x+ loc=%x+ main=%x+"><head>'))
	assert(html:find('<body><aside data-r="left"><section data-r="loc">1</section></aside>', 1, true))
	assert(wire.strip(page("1", "x")) == html:gsub(' data%-h="[^"]*"', ""))
end

function T.bad_markers()
	local function fails(html, needle)
		local ok, err = pcall(wire.split, html)
		assert(not ok and tostring(err):find(needle, 1, true), tostring(err))
	end
	fails(O("a") .. "x", "region a is not closed")
	fails("x" .. C, "endregion() without region()")
	fails(O("a") .. C .. O("a") .. C, "region a appears twice")
	assert(not pcall(wire.open, "Bad name"))
	assert(not pcall(wire.open, "1x"))
	-- escaped text can't make markers: a "<" is never in it
	assert(dk.html("<\1x>"):find("&lt;", 1, true))
end

function T.encode_decode()
	local body = wire.encode({ { "title", "", "Ünïcode" }, { "region", "main", "<p>a\nb</p>\n" }, { "go", "", "/x" } })
	assert(body:sub(1, 4) == "DK1\n")
	assert(body:find("title 9\nÜnïcode\n", 1, true), "lengths in bytes")
	local f = wire.decode(body)
	assert(#f == 3 and f[2].op == "region" and f[2].args[1] == "main" and f[2].payload == "<p>a\nb</p>\n")
	assert(f[1].payload == "Ünïcode" and f[3].op == "go" and #f[3].args == 0)
	assert(not pcall(wire.decode, "DK1\nregion main 50\nshort\n"))
end

function T.parse_have()
	local h = wire.parse_have("root=abc123 main=0f, bad=XYZ! loc=1 =2 Up=3")
	assert(h.root == "abc123" and h.main == "0f" and h.loc == "1")
	assert(h.bad == nil and h.Up == nil)
	assert(next(wire.parse_have(nil)) == nil)
	local many = {}
	for i = 1, 100 do many[#many + 1] = "r" .. i .. "=1" end
	local n = 0
	for _ in pairs(wire.parse_have(table.concat(many, " "))) do n = n + 1 end
	assert(n == 64)
end

function T.query_and_cookies()
	local q = wire.parse_query("start=15&x=a+b%21&x=2&empty=&=no")
	assert(q.start == "15" and q.x == "2" and q.empty == "" and q[""] == nil)
	assert(wire.parse_query("a=b+c").a == "b c")
	local c = wire.cookies_after({ dk_session = "old", other = "1" }, {
		{ "Set-Cookie", "dk_session=new; Path=/; HttpOnly; SameSite=Lax" },
		{ "Set-Cookie", "other=; Path=/; Max-Age=0; HttpOnly" },
		{ "X-Other", "dk_session=nope" },
	})
	assert(c.dk_session == "new" and c.other == nil)
end

return T
