-- routes.lua :: assembles the router from the feature route modules (in this order).
-- Each module returns function(router) that registers its routes. This runs once per VM
-- at warm-up: route modules must not touch dk.db at load/registration time.
local router = require("lib.router")

local r = router.new()
for _, name in ipairs({
  "routes.auth",       -- login/logout/register/verify/lostpassword/changepassword (P2)
  "routes.home",       -- GET / (P2)
  "routes.town",       -- F1
  "routes.fight",      -- F2
  "routes.community",  -- F3
  "routes.admin",      -- F4
}) do
  require(name)(r)
end
return r
