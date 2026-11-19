-- routes/admin.lua :: admin control panel (port of legacy admin.php).
-- Modules live in app/admin/; templates in templates/admin/ + templates/layout/admin.html.
local classes = require("admin.classes")
local common = require("admin.common")
local crud = require("admin.crud")
local news = require("admin.news")
local settings = require("admin.settings")
local view = require("lib.view")

local function home(req)
	return common.page(req, "Admin Home", "admin/home", {})
end

return function(r)
	local guard = common.guard
	r:get("/admin", guard, home)
	r:get("/admin/settings", guard, settings.show)
	r:post("/admin/settings", guard, settings.save)
	r:get("/admin/news", guard, news.show)
	r:post("/admin/news", guard, news.save)
	r:get("/admin/classes", guard, classes.index)
	r:get("/admin/classes/#id", guard, classes.edit)
	r:post("/admin/classes/#id", guard, classes.save)
	r:post("/admin/classes/#id/reset", guard, classes.reset)
	-- the levels editor became the per-class level tables
	r:get("/admin/levels", guard, function() return view.redirect("/admin/classes") end)
	for _, key in ipairs({ "items", "drops", "towns", "monsters", "spells", "users" }) do
		r:get("/admin/" .. key, guard, crud.list(key))
		r:get("/admin/" .. key .. "/#id", guard, crud.edit(key))
		r:post("/admin/" .. key .. "/#id", guard, crud.save(key))
	end
end
