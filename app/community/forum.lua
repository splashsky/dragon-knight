-- community/forum.lua :: the internal forum (port of forum.php), split into boards
-- (`forums` table; legacy had one list of threads, which is board 1 "General").
local auth = require("lib.auth")
local game = require("lib.game")
local notices = require("lib.notices")
local paging = require("lib.paging")
local php = require("lib.php")
local roles = require("lib.roles")
local view = require("lib.view")

local forum = {}

forum.THREADS_PER_PAGE = 20
forum.POSTS_PER_PAGE = 15
forum.TITLE_MAX = 100       -- characters (legacy column: varchar(100))
forum.CONTENT_MAX = 65535   -- bytes (legacy column: MySQL TEXT)

-- forum.php header: logged out gets a message instead of a redirect, then the usual
-- closed / verify / banned chain. Legacy never checked forumtype; we refuse unless the
-- internal forum is enabled.
function forum.guard(req)
	if not req.user then
		return view.message(req, "Forum", "The forum is for registered players only.")
	end
	local res = auth.game(req)
	if res then return res end
	if game.control().forumtype ~= 1 then
		return view.message(req, "Forum", "The forum is currently disabled.")
	end
end

local function char_len(s)
	return utf8.len(s) or #s
end

-- Validates a title (optional) and message; returns a list of error strings.
local function validate(title, content)
	local errors = {}
	if title ~= nil then
		if title == "" then
			errors[#errors + 1] = "Title is required."
		elseif not utf8.len(title) then
			errors[#errors + 1] = "Title contains invalid characters."
		elseif char_len(title) > forum.TITLE_MAX then
			errors[#errors + 1] = "Title must be " .. forum.TITLE_MAX .. " characters or less."
		end
	end
	if php.trim(content) == "" then
		errors[#errors + 1] = "Message is required."
	elseif not utf8.len(content) then
		errors[#errors + 1] = "Message contains invalid characters."
	elseif #content > forum.CONTENT_MAX then
		errors[#errors + 1] = "Message is too long."
	end
	return errors
end

-- MySQL silently cut "Re: <title>" to the column width; do the same, by characters.
local function truncate(s, n)
	if char_len(s) <= n then return s end
	local cut = utf8.offset(s, n + 1)
	return cut and s:sub(1, cut - 1) or s:sub(1, n)
end

-- Boards with admin_threads = 1 (News) only take new threads from administrators.
local function can_start_thread(board, user)
	return board.admin_threads == 0 or roles.is_admin(user)
end

local function find_board(id)
	return dk.db:first("SELECT * FROM forums WHERE id = ?", id)
end

local function no_board(req)
	return view.error(req, 404, "Forum", "That board doesn't exist.")
end

function forum.boards(req)
	local boards = dk.db:query([[
		SELECT b.id, b.name, b.description,
			(SELECT count(*) FROM forum WHERE board = b.id AND parent = 0) AS threads,
			(SELECT count(*) FROM forum WHERE board = b.id) AS posts,
			(SELECT max(newpostdate) FROM forum WHERE board = b.id AND parent = 0) AS lastpost
		FROM forums b ORDER BY b.position, b.id]])
	return view.page(req, "Forum", "community/forum/boards", { boards = boards })
end

function forum.board(req, params)
	local board = find_board(params.board)
	if not board then return no_board(req) end
	local start = paging.start(req)
	local per = forum.THREADS_PER_PAGE
	local threads = dk.db:query(
		"SELECT id, title, replies, newpostdate FROM forum WHERE board = ? AND parent = 0 " ..
		"ORDER BY newpostdate DESC, id DESC LIMIT ? OFFSET ?", board.id, per, start)
	local total = dk.db:value("SELECT count(*) FROM forum WHERE board = ? AND parent = 0", board.id)
	return view.page(req, "Forum", "community/forum/index", {
		board = board,
		threads = threads,
		can_post = can_start_thread(board, req.user),
		pages = paging.pages("/forum/" .. board.id, start, per, total),
	})
end

local function find_thread(id)
	return dk.db:first("SELECT * FROM forum WHERE id = ? AND parent = 0", id)
end

local function no_thread(req)
	return view.error(req, 404, "Forum", "That thread doesn't exist.")
end

-- Thread page; `errors`/`draft` re-show a rejected reply.
local function show_thread(req, thread, errors, draft)
	local start = paging.start(req)
	local per = forum.POSTS_PER_PAGE
	local posts = dk.db:query(
		"SELECT * FROM forum WHERE id = ? OR parent = ? ORDER BY id LIMIT ? OFFSET ?",
		thread.id, thread.id, per, start)
	local total = 1 + dk.db:value("SELECT count(*) FROM forum WHERE parent = ?", thread.id)
	return view.page(req, "Forum", "community/forum/thread", {
		board = find_board(thread.board),
		thread = thread,
		posts = posts,
		pages = paging.pages("/forum/thread/" .. thread.id, start, per, total),
		errors = errors,
		draft = draft,
	})
end

function forum.thread(req, params)
	local thread = find_thread(params.id)
	if not thread then return no_thread(req) end
	return show_thread(req, thread)
end

-- Anyone who passes the guard can reply, in every board (News threads included).
function forum.reply(req, params)
	local thread = find_thread(params.id)
	if not thread then return no_thread(req) end
	local content = req.form.content or ""
	local errors = validate(nil, content)
	if #errors > 0 then return show_thread(req, thread, errors, content) end

	local now = dk.now()
	dk.db:exec("INSERT INTO forum (board, postdate, newpostdate, author, author_id, parent, " ..
						 "replies, title, content) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)",
						 thread.board, now, now, req.user.charname, req.user.id, thread.id,
						 truncate("Re: " .. thread.title, forum.TITLE_MAX), content)
	dk.db:exec("UPDATE forum SET newpostdate = ?, replies = replies + 1 WHERE id = ?", now, thread.id)

	-- legacy went back to the first page; show the page holding the new reply instead
	local count = 1 + dk.db:value("SELECT count(*) FROM forum WHERE parent = ?", thread.id)
	local last = (count - 1) // forum.POSTS_PER_PAGE * forum.POSTS_PER_PAGE
	local url = "/forum/thread/" .. thread.id
	if last > 0 then url = url .. "?start=" .. last end
	notices.forum_reply(thread, req.user, url)
	return view.redirect(url)
end

local function admin_only(req, board)
	return view.error(req, 403, "Forum",
		"Only administrators can start threads in " .. board.name .. ". You can reply to them.")
end

local function new_form(req, board, errors, draft)
	return view.page(req, "Forum", "community/forum/new", {
		board = board,
		errors = errors,
		draft = draft or {},
		title_max = forum.TITLE_MAX,
	})
end

function forum.new_form(req, params)
	local board = find_board(params.board)
	if not board then return no_board(req) end
	if not can_start_thread(board, req.user) then return admin_only(req, board) end
	return new_form(req, board)
end

function forum.new_post(req, params)
	local board = find_board(params.board)
	if not board then return no_board(req) end
	if not can_start_thread(board, req.user) then return admin_only(req, board) end
	local title = php.trim(req.form.title)
	local content = req.form.content or ""
	local errors = validate(title, content)
	if #errors > 0 then
		return new_form(req, board, errors, { title = req.form.title, content = content })
	end
	local now = dk.now()
	dk.db:exec("INSERT INTO forum (board, postdate, newpostdate, author, author_id, parent, " ..
						 "replies, title, content) VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)",
						 board.id, now, now, req.user.charname, req.user.id, title, content)
	return view.redirect("/forum/" .. board.id)
end

return forum
