-- routes/admin.lua :: admin control panel (port of legacy admin.php).
-- Modules live in app/admin/; templates in templates/admin/ + templates/layout/admin.html.
local broadcast = require("admin.broadcast")
local classes = require("admin.classes")
local effects = require("admin.effects")
local common = require("admin.common")
local crud = require("admin.crud")
local items = require("admin.items")
local news = require("admin.news")
local server = require("admin.server")
local settings = require("admin.settings")
local spells = require("admin.spells")
local view = require("lib.view")

local function home(req)
	return common.page(req, "Admin Home", "admin/home", {})
end

return function(r)
	local guard = common.guard
	r:get("/admin", guard, home)
	r:get("/admin/server", guard, server.show)
	r:get("/admin/settings", guard, settings.show)
	r:post("/admin/settings", guard, settings.save)
	r:get("/admin/news", guard, news.show)
	r:post("/admin/news", guard, news.save)
	r:get("/admin/broadcast", guard, broadcast.show)
	r:post("/admin/broadcast", guard, broadcast.save)
	r:get("/admin/classes", guard, classes.index)
	r:get("/admin/classes/#id", guard, classes.edit)
	r:post("/admin/classes/#id", guard, classes.save)
	r:post("/admin/classes/#id/reset", guard, classes.reset)
	r:get("/admin/spells", guard, spells.index)
	r:get("/admin/spells/#id", guard, spells.edit)
	r:post("/admin/spells/#id", guard, spells.save)
	r:post("/admin/spells/#id/reset", guard, spells.reset)
	for _, name in ipairs({ "statuses", "summons", "monsters" }) do
		r:get("/admin/" .. name, guard, effects.index(name))
		r:get("/admin/" .. name .. "/#id", guard, effects.edit(name))
		r:post("/admin/" .. name .. "/#id", guard, effects.save(name))
		r:post("/admin/" .. name .. "/#id/reset", guard, effects.reset(name))
	end
	r:get("/admin/items", guard, items.index)
	r:get("/admin/items/#id", guard, items.edit)
	r:post("/admin/items/#id", guard, items.save)
	r:post("/admin/items/#id/reset", guard, items.reset)
	-- the levels editor became the per-class level tables, the drops are items
	r:get("/admin/levels", guard, function() return view.redirect("/admin/classes") end)
	r:get("/admin/drops", guard, function() return view.redirect("/admin/items") end)
	for _, key in ipairs({ "towns", "users" }) do
		r:get("/admin/" .. key, guard, crud.list(key))
		r:get("/admin/" .. key .. "/#id", guard, crud.edit(key))
		r:post("/admin/" .. key .. "/#id", guard, crud.save(key))
	end
end
