-- routes/community.lua :: forum (legacy forum.php), help pages (help*.php) and changelog.
local forum = require("community.forum")
local help = require("community.help")
local changelog = require("community.changelog")

return function(r)
	r:get("/forum", forum.guard, forum.index)
	r:get("/forum/thread/#id", forum.guard, forum.thread)
	r:get("/forum/new", forum.guard, function(req) return forum.new_form(req) end)
	r:post("/forum/new", forum.guard, forum.new_post)
	r:post("/forum/reply/#id", forum.guard, forum.reply)

	r:get("/help", help.index)
	r:get("/help/items", help.items)
	r:get("/help/spells", help.spells)
	r:get("/help/monsters", help.monsters)
	r:get("/help/levels", help.levels)

	r:get("/changelog", changelog.page)
end
