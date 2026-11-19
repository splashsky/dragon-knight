-- community/forum.lua :: the internal forum (port of forum.php).
local auth = require("lib.auth")
local game = require("lib.game")
local php = require("lib.php")
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

local function start_param(req)
  local n = php.intval(req.query.start)
  return n > 0 and n or 0
end

-- Page links for a list of `total` entries, `per` per page, currently at `start`.
local function pager(base, start, per, total)
  local pages = {}
  if total > per then
    for i = 0, (total - 1) // per do
      local s = i * per
      pages[#pages + 1] = {
        n = i + 1,
        url = s == 0 and base or view.helpers.url(base, { start = s }),
        current = start >= s and start < s + per,
      }
    end
  end
  return pages
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

function forum.index(req)
  local start = start_param(req)
  local per = forum.THREADS_PER_PAGE
  local threads = dk.db:query(
    "SELECT id, title, replies, newpostdate FROM forum WHERE parent = 0 " ..
    "ORDER BY newpostdate DESC, id DESC LIMIT ? OFFSET ?", per, start)
  local total = dk.db:value("SELECT count(*) FROM forum WHERE parent = 0")
  return view.page(req, "Forum", "community/forum/index", {
    threads = threads,
    pages = pager("/forum", start, per, total),
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
  local start = start_param(req)
  local per = forum.POSTS_PER_PAGE
  local posts = dk.db:query(
    "SELECT * FROM forum WHERE id = ? OR parent = ? ORDER BY id LIMIT ? OFFSET ?",
    thread.id, thread.id, per, start)
  local total = 1 + dk.db:value("SELECT count(*) FROM forum WHERE parent = ?", thread.id)
  return view.page(req, "Forum", "community/forum/thread", {
    thread = thread,
    posts = posts,
    pages = pager("/forum/thread/" .. thread.id, start, per, total),
    errors = errors,
    draft = draft,
  })
end

function forum.thread(req, params)
  local thread = find_thread(params.id)
  if not thread then return no_thread(req) end
  return show_thread(req, thread)
end

function forum.reply(req, params)
  local thread = find_thread(params.id)
  if not thread then return no_thread(req) end
  local content = req.form.content or ""
  local errors = validate(nil, content)
  if #errors > 0 then return show_thread(req, thread, errors, content) end

  local now = dk.now()
  dk.db:exec("INSERT INTO forum (postdate, newpostdate, author, parent, replies, title, content) " ..
             "VALUES (?, ?, ?, ?, 0, ?, ?)",
             now, now, req.user.charname, thread.id,
             truncate("Re: " .. thread.title, forum.TITLE_MAX), content)
  dk.db:exec("UPDATE forum SET newpostdate = ?, replies = replies + 1 WHERE id = ?", now, thread.id)

  -- legacy went back to the first page; show the page holding the new reply instead
  local count = 1 + dk.db:value("SELECT count(*) FROM forum WHERE parent = ?", thread.id)
  local last = (count - 1) // forum.POSTS_PER_PAGE * forum.POSTS_PER_PAGE
  local url = "/forum/thread/" .. thread.id
  if last > 0 then url = url .. "?start=" .. last end
  return view.redirect(url)
end

function forum.new_form(req, errors, draft)
  return view.page(req, "Forum", "community/forum/new", {
    errors = errors,
    draft = draft or {},
    title_max = forum.TITLE_MAX,
  })
end

function forum.new_post(req)
  local title = php.trim(req.form.title)
  local content = req.form.content or ""
  local errors = validate(title, content)
  if #errors > 0 then
    return forum.new_form(req, errors, { title = req.form.title, content = content })
  end
  local now = dk.now()
  dk.db:exec("INSERT INTO forum (postdate, newpostdate, author, parent, replies, title, content) " ..
             "VALUES (?, ?, ?, 0, 0, ?, ?)", now, now, req.user.charname, title, content)
  return view.redirect("/forum")
end

return forum
