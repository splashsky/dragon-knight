-- routes/fight.lua :: OWNED BY F2 (fight). Stub from P2.
--
-- Routes to implement (PLAN.md "URL map"; legacy fight.php):
--   GET  /fight     fight() screen          POST /fight   attack / spell / run (form buttons)
--   GET  /victory   victory()
--   GET  /drop      drop() choose slot      POST /drop    equip into slot
--   GET  /dead      dead()
-- GET / redirects to /fight while users.currentaction == "Fighting".
-- Use auth.game as the guard. See docs/APP.md.
return function(r)
end
