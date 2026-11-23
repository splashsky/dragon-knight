-- session.lua :: server-side login sessions (PLAN.md "Data model").
--
-- Cookie dk_session = 64 hex chars (32 random bytes); the DB stores only
-- hex(sha256(token)). Normal sessions: browser-session cookie, server expiry 1 day,
-- sliding. "Remember me": Max-Age 1 year, server expiry 1 year, sliding.
local cookie = require("lib.cookie")
local json = require("lib.json")
local presence = require("lib.presence")
local users = require("lib.users")

local session = {}

session.COOKIE = "dk_session"
session.TTL = 86400
session.REMEMBER_TTL = 31536000

local function hash(token)
	return dk.crypto.hex(dk.crypto.sha256(token))
end

local function ttl_of(remember)
	return remember and session.REMEMBER_TTL or session.TTL
end

local SESSION_COLUMNS = { "token_hash", "user_id", "csrf", "created", "expires", "remember" }
local SESSION_SQL = "SELECT s.token_hash AS s_token_hash, s.user_id AS s_user_id, s.csrf AS s_csrf, " ..
	"s.created AS s_created, s.expires AS s_expires, s.remember AS s_remember, u.* " ..
	"FROM sessions s LEFT JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?"

-- Loads req.session and req.user from the cookie. Touches users.onlinetime (legacy
-- cookies.php did this on every authenticated request; a player not online yet is
-- announced, lib/presence.lua) and slides the expiry.
function session.load(req)
	local token = req.cookies[session.COOKIE]
	if not token then return nil end
	if #token ~= 64 or not token:find("^%x+$") then
		cookie.clear(req, session.COOKIE)
		return nil
	end
	local now = dk.now()
	local th = hash(token)
	-- the session and its user in one query
	local row = dk.db:first(SESSION_SQL, th)
	local s, user = nil, nil
	if row then
		s = {}
		for _, k in ipairs(SESSION_COLUMNS) do
			s[k], row["s_" .. k] = row["s_" .. k], nil
		end
		user = row.id and s.expires > now and row or nil
	end
	if not user then
		if s then dk.db:exec("DELETE FROM sessions WHERE token_hash = ?", th) end
		cookie.clear(req, session.COOKIE)
		return nil
	end

	local remember = s.remember == 1
	local ttl = ttl_of(remember)
	local left = s.expires - now
	if left < ttl - 60 then
		s.expires = now + ttl
		dk.db:exec("UPDATE sessions SET expires = ? WHERE token_hash = ?", s.expires, th)
		-- legacy re-sent the remember-me cookie with a fresh year; do it at most daily
		if remember and left < ttl - 86400 then
			cookie.set(req, session.COOKIE, token, { max_age = ttl })
		end
	end
	presence.touch(user, now)
	-- (the row as presence.touch left it, in the database too: the page's layout reads it again)
	users.remember(user)
	req.session, req.user = s, user
	return user
end

-- Logs user_id in: new random token (never reuses a pre-login one), cookie queued.
function session.create(req, user_id, remember)
	local now = dk.now()
	local token = dk.crypto.hex(dk.crypto.random(32))
	local s = {
		token_hash = hash(token),
		user_id = user_id,
		csrf = dk.crypto.hex(dk.crypto.random(32)),
		created = now,
		expires = now + ttl_of(remember),
		remember = remember and 1 or 0,
	}
	dk.db:exec("DELETE FROM sessions WHERE expires <= ?", now)
	if req.session then
		dk.db:exec("DELETE FROM sessions WHERE token_hash = ?", req.session.token_hash)
	end
	dk.db:exec("INSERT INTO sessions (token_hash, user_id, csrf, created, expires, remember) " ..
						 "VALUES (?, ?, ?, ?, ?, ?)", s.token_hash, s.user_id, s.csrf, s.created, s.expires,
						 s.remember)
	cookie.set(req, session.COOKIE, token, { max_age = remember and session.REMEMBER_TTL or nil })
	req.session = s
	req.user = users.get(user_id)
	return s
end

-- A short public id of a session (pages carry it so the `logout` event only closes the
-- streams of the session that logged out): not the token, nor its hash.
function session.live_id(s)
	return dk.crypto.hex(dk.crypto.sha256("live:" .. s.token_hash)):sub(1, 16)
end

-- Tells the user's open pages (event streams, user:<id>) they were logged out: those of
-- one session (`s`), or all of them (nil).
function session.publish_logout(user_id, s)
	local data = s and { session = session.live_id(s) } or { all = true }
	dk.publish("user:" .. user_id, "logout", json.encode(data))
end

-- Logs the current request out (deletes the row, clears the cookie, tells its pages).
function session.destroy(req)
	if req.session then
		dk.db:exec("DELETE FROM sessions WHERE token_hash = ?", req.session.token_hash)
		session.publish_logout(req.session.user_id, req.session)
	end
	if req.cookies[session.COOKIE] then cookie.clear(req, session.COOKIE) end
	req.session, req.user = nil, nil
end

-- Ends every session of a user (password change/reset, bans).
function session.destroy_user(user_id)
	dk.db:exec("DELETE FROM sessions WHERE user_id = ?", user_id)
end

return session
