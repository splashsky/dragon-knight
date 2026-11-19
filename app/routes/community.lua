-- routes/community.lua :: OWNED BY F3 (forum/help/news). Stub from P2.
--
-- Routes to implement (PLAN.md "URL map"; legacy forum.php, help*.php):
--   GET  /forum                       thread list (legacy donothing; ?start=n for paging)
--   GET  /forum/thread/#id[?start=n]  showthread()
--   GET  /forum/new                   newthread() form   POST /forum/new        create thread
--   POST /forum/reply/#id             reply()
--   GET  /help, /help/items, /help/spells, /help/monsters, /help/levels
-- Forum: auth.game guard (legacy forum.php: "The forum is for registered players only.").
-- Help pages are public (no guard). See docs/APP.md.
return function(r)
end
