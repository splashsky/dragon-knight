-- control.lua :: the control row (id 1: the game's settings), kept for the request
-- (lib/cache.lua: a write to it is seen at once). game.control() is the usual way in.
local cache = require("lib.cache")

local control = {}

local store = cache.store("control", { tables = { "control" }, size = 2 })

local DEFAULT = { id = 1, gamename = "Dragon Knight", gamesize = 250, gameopen = 1, forumtype = 0, forumaddress = "",
	verifyemail = 0, shownews = 0, showbabble = 0, showonline = 0, gameurl = "", adminemail = "", inventory_size = 12 }

-- The row (shared: don't change it), or the defaults when there is none.
function control.row()
	return store:fetch(1, function() return dk.db:first("SELECT * FROM control WHERE id = 1") end) or DEFAULT
end

-- Read it again.
function control.reload()
	store:clear()
	return control.row()
end

return control
