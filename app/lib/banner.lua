-- banner.lua :: the administrators' broadcast banner (/admin/broadcast): one short text
-- shown at the top of every page until it is cleared or expires. Stored in the control
-- row (banner, banner_id: +1 per new banner, banner_expires: unix time, 0 = never), sent
-- live on the `notices` channel: `banner` { id, text, expires, ttl } and `clear` { id }.
-- A browser that dismissed banner N has the cookie dk_banner=N and isn't shown it again.
local game = require("lib.game")
local json = require("lib.json")

local banner = {}

banner.CHANNEL = "notices"
banner.COOKIE = "dk_banner"
banner.MAX_CHARS = 200
banner.MAX_MINUTES = 60 * 24 * 365

-- The active banner { id, text, expires, ttl } or nil (none, expired, or `req`'s browser
-- dismissed it).
function banner.current(req)
	local c = game.control()
	if not c.banner or c.banner == "" then return nil end
	local now = dk.now()
	local expires = c.banner_expires or 0
	if expires ~= 0 and expires <= now then return nil end
	if req and req.cookies and req.cookies[banner.COOKIE] == tostring(c.banner_id) then return nil end
	return { id = c.banner_id, text = c.banner, expires = expires ~= 0 and expires or nil,
					 ttl = expires ~= 0 and expires - now or nil }
end

-- Shows `text` from now on, for `minutes` (nil: until cleared). Returns the banner.
function banner.set(text, minutes)
	local now = dk.now()
	local expires = minutes and now + minutes * 60 or 0
	dk.db:exec("UPDATE control SET banner = ?, banner_id = banner_id + 1, banner_expires = ? WHERE id = 1",
						 text, expires)
	local id = game.reload_control().banner_id
	local b = { id = id, text = text, expires = minutes and expires or nil, ttl = minutes and minutes * 60 or nil }
	dk.publish(banner.CHANNEL, "banner", json.encode(b))
	return b
end

-- Removes the banner (if any).
function banner.clear()
	local c = game.control()
	if c.banner == "" then return false end
	dk.db:exec("UPDATE control SET banner = '', banner_expires = 0 WHERE id = 1")
	game.reload_control()
	dk.publish(banner.CHANNEL, "clear", json.encode({ id = c.banner_id }))
	return true
end

return banner
