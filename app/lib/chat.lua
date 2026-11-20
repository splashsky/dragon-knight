-- chat.lua :: the Babble Box, the game's global chat (docs/APP.md "Chat"). Messages are
-- `babble` rows (text stored raw, escaped on output); new ones and deletions go out on the
-- `babble` event channel: `babble` { id, author, text, time } and `delete` { id }.
local json = require("lib.json")
local php = require("lib.php")

local chat = {}

chat.CHANNEL = "babble"
chat.MAX_CHARS = 120   -- the form's maxlength (longer text is cut, like legacy)
chat.HISTORY = 50      -- messages shown on a page
chat.INTERVAL = 2      -- seconds between two messages of one player (whole seconds)

-- legacy makesafe() minus the HTML hacks: no tabs or line breaks, at most MAX_CHARS
-- characters (bytes if it isn't valid UTF-8).
function chat.clean(s)
	s = tostring(s or ""):gsub("[\t\r\n]", "")
	if (utf8.len(s) or #s) > chat.MAX_CHARS then
		local cut = utf8.len(s) and utf8.offset(s, chat.MAX_CHARS + 1) or chat.MAX_CHARS + 1
		s = s:sub(1, cut - 1)
	end
	return s
end

-- The last HISTORY messages, oldest first.
function chat.history()
	local rows = dk.db:query("SELECT id, posttime, author, author_id, babble FROM babble ORDER BY id DESC LIMIT ?",
													 chat.HISTORY)
	local out = {}
	for i = #rows, 1, -1 do out[#out + 1] = rows[i] end
	return out
end

-- What a message looks like in events and JSON answers (when: the time as the page shows
-- it; delete: the address administrators delete it with; live.js fills the page's
-- chat-post prototype, layout/chat.html, with these).
function chat.event(row)
	return { id = row.id, author = row.author, text = row.babble, time = row.posttime,
		when = php.datetime(row.posttime), delete = "/babble/" .. row.id .. "/delete" }
end

-- Seconds `user` has to wait before posting again (0: may post now).
function chat.wait(user, now)
	local last = dk.db:value("SELECT max(posttime) FROM babble WHERE author_id = ?", user.id)
	if not last or now < last then return 0 end
	return math.max(0, chat.INTERVAL - (now - last))
end

-- Posts `text` as `user`. Returns the message (nil for a blank one), or nil and the
-- seconds to wait when the player posted less than INTERVAL seconds ago.
function chat.post(user, text)
	text = chat.clean(text)
	if php.trim(text) == "" then return nil end
	local now = dk.now()
	local wait = chat.wait(user, now)
	if wait > 0 then return nil, wait end
	local _, id = dk.db:exec("INSERT INTO babble (posttime, author, author_id, babble) VALUES (?, ?, ?, ?)",
													 now, user.charname, user.id, text)
	local row = { id = id, posttime = now, author = user.charname, author_id = user.id, babble = text }
	dk.publish(chat.CHANNEL, "babble", json.encode(chat.event(row)))
	return row
end

-- Deletes message `id`; returns whether there was one.
function chat.delete(id)
	local n = dk.db:exec("DELETE FROM babble WHERE id = ?", id)
	if n == 0 then return false end
	dk.publish(chat.CHANNEL, "delete", json.encode({ id = id }))
	return true
end

return chat
