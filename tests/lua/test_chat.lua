-- Unit tests for the pure parts of app/lib/chat.lua and app/lib/presence.lua.
local chat = require("lib.chat")
local presence = require("lib.presence")
local T = {}

function T.clean()
	assert(chat.clean(nil) == "")
	assert(chat.clean("a\tb\r\nc") == "abc")
	assert(chat.clean(string.rep("x", 130)) == string.rep("x", 120))
	-- characters, not bytes: 130 two-byte letters keep 120 of them
	local s = chat.clean(string.rep("é", 130))
	assert(utf8.len(s) == 120 and #s == 240)
	-- invalid UTF-8 is cut by bytes
	assert(#chat.clean(string.rep("\255", 130)) == 120)
	assert(chat.clean("<b>&</b>") == "<b>&</b>")   -- stored raw, escaped on output
end

function T.event()
	local e = chat.event({ id = 7, posttime = 100, author = "A", author_id = 3, babble = "hi" })
	assert(e.id == 7 and e.time == 100 and e.author == "A" and e.text == "hi" and e.author_id == nil)
end

function T.config_seconds()
	local saved = { dk.config.online_seconds, dk.config.presence_sweep_seconds }
	dk.config.online_seconds, dk.config.presence_sweep_seconds = nil, nil
	assert(presence.window() == 600 and presence.sweep_interval() == 60)
	dk.config.online_seconds, dk.config.presence_sweep_seconds = 2, "5"
	assert(presence.window() == 2 and presence.sweep_interval() == 5)
	dk.config.online_seconds, dk.config.presence_sweep_seconds = 0, "soon"
	assert(presence.window() == 600 and presence.sweep_interval() == 60)
	dk.config.online_seconds, dk.config.presence_sweep_seconds = saved[1], saved[2]
end

-- Who's online costs what the players online cost, not a scan of every account: the count
-- (every game page) and the list (the town page) read the partial index users_online.
function T.online_index()
	for _, sql in ipairs({ presence.COUNT_SQL, presence.LIST_SQL }) do
		local plan = dk.db:query("EXPLAIN QUERY PLAN " .. sql)
		assert(#plan == 1 and plan[1].detail:find("USING COVERING INDEX users_online", 1, true),
			sql .. ": " .. tostring(plan[1] and plan[1].detail))
	end
end

return T
