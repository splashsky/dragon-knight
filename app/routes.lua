-- routes.lua :: assembles the router from the feature route modules (in this order).
-- Each module returns function(router) that registers its routes. This runs once per VM
-- at warm-up: route modules must not touch dk.db at load/registration time.
local router = require("lib.router")

local r = router.new()
for _, name in ipairs({
	"routes.auth",       -- login/logout/register/verify/lostpassword/changepassword
	"routes.home",       -- GET /
	"routes.town",       -- town, explore, heal spells, character/map, babble
	"routes.fight",      -- fight, victory, drops
	"routes.community",  -- forum, help
	"routes.admin",      -- admin panel
	"routes.theme",      -- POST /theme (theme selector)
	"routes.live",       -- GET /live (event stream)
	"routes.test",       -- /__test/* (only with test_routes = true)
}) do
	require(name)(r)
end
return r
