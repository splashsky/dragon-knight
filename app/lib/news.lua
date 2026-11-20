-- news.lua :: news posts (the town news box, the /news archive, admin posting).
-- Every post has a discussion thread in the forum's News board (forums.id = news.BOARD).
local game = require("lib.game")
local php = require("lib.php")

local news = {}

news.BOARD = 2              -- forums row for news threads (seeded, admin_threads = 1)
news.PER_PAGE = 10          -- /news
news.TITLE_MAX = 100        -- characters, like forum titles
news.DEFAULT_TITLE_LEN = 60 -- characters of the first line used when the title is empty

-- Lines of `s` with CRLF / CR line ends normalized.
local function lines(s)
	s = tostring(s or ""):gsub("\r\n?", "\n")
	local out = {}
	for line in (s .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
	return out
end

local function blank(line)
	return not line:find("%S")
end

-- `s` cut to `n` characters (bytes if it isn't valid UTF-8) plus "...", or unchanged.
function news.shorten(s, n)
	local len = utf8.len(s)
	if (len or #s) <= n then return s end
	local cut = len and utf8.offset(s, n + 1) - 1 or n
	return php.trim(s:sub(1, cut)) .. "..."
end

-- First paragraph of a post: the lines up to the first blank line (only whitespace),
-- skipping leading blank lines. Returns the paragraph and whether anything other than
-- whitespace follows it.
function news.first_paragraph(text)
	local ls = lines(text)
	local i = 1
	while ls[i] and blank(ls[i]) do i = i + 1 end
	local para = {}
	while ls[i] and not blank(ls[i]) do
		para[#para + 1] = ls[i]
		i = i + 1
	end
	for j = i, #ls do
		if not blank(ls[j]) then return table.concat(para, "\n"), true end
	end
	return table.concat(para, "\n"), false
end

-- Title for a post submitted without one: its first non-blank line, trimmed and
-- shortened to DEFAULT_TITLE_LEN characters.
function news.default_title(content)
	for _, line in ipairs(lines(content)) do
		local t = php.trim(line)
		if t ~= "" then return news.shorten(t, news.DEFAULT_TITLE_LEN) end
	end
	return ""
end

-- Text of the link to a post's thread.
function news.reply_label(replies)
	replies = replies or 0
	if replies == 0 then return "Reply" end
	if replies == 1 then return "1 reply" end
	return replies .. " replies"
end

local SELECT = [[
SELECT n.id, n.postdate, n.title, n.content, n.author_id, n.thread_id,
	coalesce(u.charname, 'Unknown') AS author, t.id AS thread_found, t.replies AS thread_replies
FROM news n
LEFT JOIN users u ON u.id = n.author_id
LEFT JOIN forum t ON t.id = n.thread_id AND t.parent = 0
]]

-- Adds thread_url / thread_label when the built-in forum is on and the thread exists.
local function decorate(p)
	if p and p.thread_found and game.control().forumtype == 1 then
		p.thread_url = "/forum/thread/" .. p.thread_found
		p.thread_label = news.reply_label(p.thread_replies)
	end
	return p
end

-- Newest post with `excerpt` (first paragraph) and `more` (something was cut), or nil.
function news.latest()
	local p = decorate(dk.db:first(SELECT .. "ORDER BY n.id DESC LIMIT 1"))
	if p then p.excerpt, p.more = news.first_paragraph(p.content) end
	return p
end

function news.get(id)
	return decorate(dk.db:first(SELECT .. "WHERE n.id = ?", id))
end

-- One page of posts, newest first (by id, like the town box), and the total count.
function news.page(start, per)
	local posts = dk.db:query(SELECT .. "ORDER BY n.id DESC LIMIT ? OFFSET ?", per, start)
	for _, p in ipairs(posts) do decorate(p) end
	return posts, dk.db:value("SELECT count(*) FROM news")
end

-- Starts a thread in the News board; returns its id.
function news.create_thread(title, content, author, author_id, postdate)
	local _, id = dk.db:exec(
		"INSERT INTO forum (board, postdate, newpostdate, author, author_id, parent, replies, " ..
		"title, content) VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)",
		news.BOARD, postdate, postdate, author, author_id, title, content)
	return id
end

-- Posts news as `user` (an empty title gets the default) with its discussion thread,
-- whatever the forum setting, so the threads exist if the built-in forum is enabled later.
-- Returns the post id and its title.
function news.post(user, title, content)
	if title == "" then title = news.default_title(content) end
	local now = dk.now()
	local thread = news.create_thread(title, content, user.charname, user.id, now)
	local _, id = dk.db:exec(
		"INSERT INTO news (postdate, title, content, author_id, thread_id) VALUES (?, ?, ?, ?, ?)",
		now, title, content, user.id, thread)
	return id, title
end

-- `dk install`: posts without an author (the seeded one) become `admin`'s; posts without a
-- title or thread get them.
function news.adopt(admin)
	dk.db:exec("UPDATE news SET author_id = ? WHERE author_id IS NULL", admin.id)
	for _, p in ipairs(dk.db:query(SELECT .. "WHERE n.thread_id IS NULL ORDER BY n.id")) do
		local title = p.title ~= "" and p.title or news.default_title(p.content)
		local thread = news.create_thread(title, p.content, p.author, p.author_id, p.postdate)
		dk.db:exec("UPDATE news SET title = ?, thread_id = ? WHERE id = ?", title, thread, p.id)
	end
end

return news
