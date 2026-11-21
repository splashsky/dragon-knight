-- auth.lua :: password hashing + route guards.
local game = require("lib.game")
local roles = require("lib.roles")
local view = require("lib.view")

local auth = {}

auth.DEFAULT_ITERATIONS = 210000

function auth.iterations()
	local n = math.tointeger(tonumber(dk.config.pbkdf2_iterations))
	if not n or n < 1 then return auth.DEFAULT_ITERATIONS end
	return n
end

-- "pbkdf2$<iters>$<salt hex>$<hash hex>" (PBKDF2-HMAC-SHA256, 16-byte salt, 32-byte key)
function auth.hash_password(password, iters)
	iters = iters or auth.iterations()
	local salt = dk.crypto.random(16)
	local key = dk.crypto.pbkdf2(password, salt, iters, 32)
	return string.format("pbkdf2$%d$%s$%s", iters, dk.crypto.hex(salt), dk.crypto.hex(key))
end

local function unhex(h)
	return (h:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
end

local function parse(stored)
	if type(stored) ~= "string" then return nil end
	local iters, salt, key = stored:match("^pbkdf2%$(%d+)%$(%x+)%$(%x+)$")
	iters = math.tointeger(tonumber(iters))
	if not iters or iters < 1 or iters > 100000000 or #salt % 2 == 1 or #key % 2 == 1 then return nil end
	return iters, unhex(salt), key
end

-- Constant-time check. Unknown/garbled hashes never match (a dummy derivation still runs
-- so timing doesn't reveal which usernames exist).
function auth.verify_password(password, stored)
	local iters, salt, key = parse(stored)
	if not iters then
		dk.crypto.pbkdf2(tostring(password), "dk-dummy-salt", auth.iterations(), 32)
		return false
	end
	local got = dk.crypto.hex(dk.crypto.pbkdf2(tostring(password), salt, iters, #key // 2))
	return dk.crypto.eq(got, key)
end

function auth.needs_rehash(stored)
	local iters = parse(stored)
	return iters ~= auth.iterations()
end

-- Random password/code: n uppercase letters (legacy: chr(rand(65,90)) x 8), from the CSPRNG.
function auth.random_letters(n)
	local bytes, out = dk.crypto.random(n * 2), {}
	for i = 1, n do
		local v = string.byte(bytes, 2 * i - 1) * 256 + string.byte(bytes, 2 * i)
		out[i] = string.char(65 + v % 26)
	end
	return table.concat(out)
end

---------------------------------------------------------------------------------------
-- Guards: function(req) -> nil to continue, or a response.

-- Any logged-in user.
function auth.login(req)
	if not req.user then return view.redirect("/login") end
end

-- The game guard chain from legacy index.php.
function auth.game(req)
	if not req.user then return view.redirect("/login") end
	local control = game.control()
	if control.gameopen == 0 then
		return view.message(req, "Game Closed",
			"The game is currently closed for maintanence. Please check back later.")
	end
	if control.verifyemail == 1 and tostring(req.user.verify) ~= "1" then
		return view.redirect("/verify")
	end
	if roles.is_blocked(req.user) then
		return view.error(req, 403, "Blocked", "Your account has been blocked. Please try back later.")
	end
end

-- Admin control panel (legacy admin.php: login + authlevel 1; no gameopen check).
function auth.admin(req)
	if not req.user then return view.redirect("/login") end
	if not roles.is_admin(req.user) then
		return view.error(req, 403, "Error",
			"You must have administrator privileges to use the control panel.")
	end
end

return auth
