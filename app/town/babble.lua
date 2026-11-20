-- town/babble.lua :: the Babble Box's routes (legacy index.php babblebox(); the chat itself
-- is lib/chat.lua). Forms post here and come back to their page (`back`); live.js posts
-- with fetch and `Accept: application/json` and gets JSON instead of a redirect.
local chat = require("lib.chat")
local json = require("lib.json")
local view = require("lib.view")

local babble = {}

-- GET /babble: the chat on a page of its own (it was the town page's iframe).
function babble.show(req)
	return view.page(req, "Babble Box", "town/babble", { chat = view.chat(req, true), online = view.online() },
									 { chat_inline = true })
end

local function too_fast(req, wait)
	local msg = "You are sending messages too fast. Please wait a moment and try again."
	local headers = { { "Retry-After", tostring(wait) } }
	if view.wants_json(req) then return view.json({ error = msg, wait = wait }, 429, headers) end
	return view.error(req, 429, "Babble Box", msg, { headers = headers })
end

-- POST /babble (babble, back): blank messages are ignored, longer ones cut to
-- chat.MAX_CHARS; at most one message per chat.INTERVAL seconds (429).
function babble.post(req)
	req.quiet = true   -- the chat's own events tell the pages (main.lua publish_stale)
	local row, wait = chat.post(req.user, req.form.babble)
	if wait then return too_fast(req, wait) end
	if view.wants_json(req) then
		return view.json({ message = row and chat.event(row) or json.null })
	end
	return view.redirect(view.back_to(req, "/babble"))
end

-- POST /babble/#id/delete (administrators): the message goes, on every open page too.
function babble.delete(req, params)
	req.quiet = true
	if req.user.authlevel ~= 1 then
		local msg = "Only administrators can delete messages."
		if view.wants_json(req) then return view.json({ error = msg }, 403) end
		return view.error(req, 403, "Babble Box", msg)
	end
	local found = chat.delete(params.id)
	if view.wants_json(req) then
		return view.json({ deleted = found }, found and 200 or 404)
	end
	return view.redirect(view.back_to(req, "/babble"))
end

return babble
