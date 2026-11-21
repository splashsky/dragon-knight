-- scene.lua :: a change of the player's state (arriving in a town, setting out, a fight
-- beginning, a victory, a death, a getaway) as an event for the live client: the page
-- fades out through a caption (a title and a line of details) and the new one fades in
-- (public/js/scene.js; docs/APP.md "Scenes"). Live requests only: a page load just shows
-- the new page.
local json = require("lib.json")

local scene = {}

-- Adds a scene to response res (a redirect: main.lua carries its events to the page it
-- lands on) and returns res. kind: "town", "explore", "fight", "victory", "death" or
-- "escape"; title (short, large) and detail (a sentence), plain text; page: the page it
-- lands on is drawn like the caption (the victory page): no caption over it, the page
-- fades in itself and stays.
function scene.add(req, res, kind, title, detail, page)
	if not req.live then return res end
	res.events = res.events or {}
	res.events[#res.events + 1] = { kind = "scene",
		json = json.encode({ kind = kind, title = title, detail = detail or "", page = page or nil }) }
	return res
end

return scene
