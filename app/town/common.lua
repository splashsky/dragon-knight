-- town/common.lua :: helpers shared by the town/explore/heal modules.
local game = require("lib.game")
local view = require("lib.view")

local common = {}

-- Guard: legacy travelto()/move() bounce a fighting player back to the fight; the
-- other town actions do the same here (legacy had no check, but no UI path reached them).
function common.not_fighting(req)
	if req.user.currentaction == "Fighting" then return view.redirect("/fight") end
end

-- One of the short legacy display("...") messages from templates/town/message.html.
function common.message(req, title, key, ctx)
	ctx = ctx or {}
	ctx.key = key
	return view.page(req, title, "town/message", ctx)
end

-- Legacy "Cheat attempt detected." page: used whenever a request asks for something the
-- UI never offers (item not sold here, unknown town, ...).
function common.cheat(req)
	return common.message(req, "Error", "cheat")
end

-- The town at the player's coordinates (legacy towns.php looked it up the same way).
function common.town_here(req)
	return game.current_town(req.user)
end

return common
