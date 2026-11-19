-- csrf.lua :: CSRF tokens. main.lua verifies EVERY POST before the route handler runs,
-- so every POST form must contain {{{ csrf_field() }}}.
--
-- Logged in: the token is sessions.csrf (random, per session).
-- Logged out (login/register/verify/lostpassword/changepassword forms): signed
-- double-submit. A random HttpOnly cookie dk_csrf is set and the form carries
-- hex(hmac_sha256(config.secret, "csrf:" .. cookie)). An attacker can neither read the
-- cookie nor compute the HMAC. Either kind of token is accepted on any POST.
local cookie = require("lib.cookie")

local csrf = {}

csrf.FIELD = "csrf"
csrf.COOKIE = "dk_csrf"

local function secret()
	local s = dk.config.secret
	if type(s) ~= "string" or s == "" then return "dk-insecure-default-secret" end
	return s
end

local function anon_token(seed)
	return dk.crypto.hex(dk.crypto.hmac_sha256(secret(), "csrf:" .. seed))
end

local function valid_seed(v)
	return type(v) == "string" and #v == 64 and v:find("^%x+$") ~= nil
end

-- The token to embed in forms for this request.
function csrf.token(req)
	if req.session then return req.session.csrf end
	local seed = req.cookies[csrf.COOKIE]
	if not valid_seed(seed) then
		seed = dk.crypto.hex(dk.crypto.random(32))
		req.cookies[csrf.COOKIE] = seed
		cookie.set(req, csrf.COOKIE, seed)
	end
	return anon_token(seed)
end

-- '<input type="hidden" name="csrf" value="...">' (trusted HTML: use {{{ }}}).
function csrf.field(req)
	return '<input type="hidden" name="' .. csrf.FIELD .. '" value="' .. csrf.token(req) .. '">'
end

function csrf.verify(req)
	local sent = req.form[csrf.FIELD] or req.headers["x-csrf-token"]
	if type(sent) ~= "string" or #sent ~= 64 then return false end
	if req.session and dk.crypto.eq(sent, req.session.csrf) then return true end
	local seed = req.cookies[csrf.COOKIE]
	return valid_seed(seed) and dk.crypto.eq(sent, anon_token(seed))
end

return csrf
