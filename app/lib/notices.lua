-- notices.lua :: small live notices (toasts) for open pages. Not stored: a player who
-- isn't online doesn't get them later.
--   notices   `news`  { id, title, author, url }: a news post (everyone)
--   user:<id> `reply` { thread, title, author, url }: a reply in a forum thread the
--             player started or posted in (not to the one who replied)
local json = require("lib.json")

local notices = {}

notices.REPLY_MAX = 200   -- players told about one reply (dk.publish allows 256 per request)

function notices.news(id, title, author)
	dk.publish("notices", "news", json.encode({ id = id, title = title, author = author, url = "/news/" .. id }))
end

-- A reply by `author` (a users row) in `thread` (its forum row); `url` shows the reply.
function notices.forum_reply(thread, author, url)
	local ids = dk.db:query([[
		SELECT author_id AS id, max(id) AS latest FROM forum
		WHERE (id = ? OR parent = ?) AND author_id IS NOT NULL AND author_id <> ?
		GROUP BY author_id ORDER BY latest DESC LIMIT ?]], thread.id, thread.id, author.id, notices.REPLY_MAX)
	if #ids == 0 then return end
	local data = json.encode({ thread = thread.id, title = thread.title, author = author.charname, url = url })
	for _, r in ipairs(ids) do dk.publish("user:" .. r.id, "reply", data) end
end

return notices
