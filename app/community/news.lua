-- community/news.lua :: GET /news (all posts, paged) and GET /news/#id.
local news = require("lib.news")
local paging = require("lib.paging")
local view = require("lib.view")

local handlers = {}

function handlers.index(req)
	local start = paging.start(req)
	local posts, total = news.page(start, news.PER_PAGE)
	return view.page(req, "News", "community/news/index", {
		posts = posts,
		pages = paging.pages("/news", start, news.PER_PAGE, total),
	})
end

function handlers.show(req, params)
	local post = news.get(params.id)
	if not post then return view.error(req, 404, "News", "That news post doesn't exist.") end
	return view.page(req, post.title, "community/news/show", { post = post })
end

return handlers
