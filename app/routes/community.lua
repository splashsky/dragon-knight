-- routes/community.lua :: forum (legacy forum.php), news archive, help pages (help*.php)
-- and changelog.
local auth = require("lib.auth")
local forum = require("community.forum")
local help = require("community.help")
local changelog = require("community.changelog")
local news = require("community.news")
local view = require("lib.view")

return function(r)
	r:get("/forum", forum.guard, forum.boards)
	r:get("/forum/#board", forum.guard, forum.board)
	r:get("/forum/#board/new", forum.guard, forum.new_form)
	r:post("/forum/#board/new", forum.guard, forum.new_post)
	r:get("/forum/thread/#id", forum.guard, forum.thread)
	r:post("/forum/reply/#id", forum.guard, forum.reply)
	-- before boards, new threads went to /forum/new
	r:get("/forum/new", function() return view.redirect("/forum/1/new") end)

	r:get("/news", auth.game, news.index)
	r:get("/news/#id", auth.game, news.show)

	r:get("/help", help.index)
	r:get("/help/items", help.items)
	r:get("/help/spells", help.spells)
	r:get("/help/monsters", help.monsters)
	r:get("/help/levels", help.levels)

	r:get("/changelog", changelog.page)
end
