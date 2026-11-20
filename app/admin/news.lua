-- admin/news.lua :: GET/POST /admin/news (legacy admin.php addnews(), plus a title, the
-- author and a discussion thread in the forum's News board).
local common = require("admin.common")
local news = require("lib.news")
local notices = require("lib.notices")
local php = require("lib.php")
local view = require("lib.view")

local handlers = {}

local function form(req, ctx)
	ctx.title_max = news.TITLE_MAX
	return common.page(req, "Add News", "admin/news", ctx)
end

function handlers.show(req)
	return form(req, { saved = req.query.saved ~= nil })
end

function handlers.save(req)
	local title = php.trim(common.field(req, "title"))
	local content = common.field(req, "content")
	local errors = {}
	if not utf8.len(title) then
		errors[#errors + 1] = "Title contains invalid characters."
	elseif utf8.len(title) > news.TITLE_MAX then
		errors[#errors + 1] = "Title must be " .. news.TITLE_MAX .. " characters or less."
	end
	if php.trim(content) == "" then errors[#errors + 1] = "Content is required." end
	if #errors > 0 then
		return form(req, { errors = errors, title = common.field(req, "title"), content = content })
	end
	-- stored raw and escaped on output (legacy printed it as HTML)
	local id, final_title = news.post(req.user, title, content)
	notices.news(id, final_title, req.user.charname)
	return view.redirect("/admin/news?saved=1")
end

return handlers
