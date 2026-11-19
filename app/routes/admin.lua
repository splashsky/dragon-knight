-- routes/admin.lua :: OWNED BY F4 (admin control panel). Stub from P2.
--
-- Routes to implement (PLAN.md "URL map"; legacy admin.php):
--   GET  /admin                                   admin home
--   GET  /admin/settings     POST /admin/settings  main settings (control row; call game.reload_control())
--   GET  /admin/news         POST /admin/news      add news post
--   GET  /admin/{items,drops,towns,monsters,spells,levels,users}             lists
--   GET  /admin/{items,drops,towns,monsters,spells,levels,users}/#id         edit form
--   POST /admin/{items,drops,towns,monsters,spells,levels,users}/#id         save
-- Use auth.admin as the guard; render with { layout = "admin" } and create
-- templates/layout/admin.html (yours). See docs/APP.md.
return function(r)
end
