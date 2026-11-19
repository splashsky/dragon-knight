-- admin/news.lua :: GET/POST /admin/news (legacy admin.php addnews()).
local common = require("admin.common")
local view = require("lib.view")

local news = {}

function news.show(req)
  return common.page(req, "Add News", "admin/news", { saved = req.query.saved ~= nil })
end

function news.save(req)
  local content = common.field(req, "content")
  if content == "" then
    return common.page(req, "Add News", "admin/news",
                       { errors = { "Content is required." }, content = content })
  end
  -- stored raw and escaped on output (legacy printed it as HTML)
  dk.db:exec("INSERT INTO news (postdate, content) VALUES (?, ?)", dk.now(), content)
  return view.redirect("/admin/news?saved=1")
end

return news
