-- cli/user.lua :: `dk user ...` account administration from the shell.
local auth = require("lib.auth")
local session = require("lib.session")

local USAGE = [[
usage: dk user list
			 dk user passwd <username> <newpassword>
			 dk user admin <username>
]]

local function find(username)
	local u = dk.db:first("SELECT * FROM users WHERE username = ?", username)
	if not u then io.stderr:write("dk user: no user named '", username, "'\n") end
	return u
end

local commands = {}

function commands.list()
	local rows = dk.db:query("SELECT id, username, charname, email, authlevel, verify, level " ..
													 "FROM users ORDER BY id")
	print(string.format("%-5s %-20s %-20s %-30s %-5s %-8s %s", "id", "username", "charname",
											"email", "auth", "verified", "level"))
	for _, u in ipairs(rows) do
		print(string.format("%-5d %-20s %-20s %-30s %-5d %-8s %d", u.id, u.username, u.charname,
												u.email, u.authlevel, u.verify == "1" and "yes" or "no", u.level))
	end
	return 0
end

function commands.passwd(username, password)
	if not password or password == "" then return nil end
	local u = find(username)
	if not u then return 1 end
	dk.db:exec("UPDATE users SET password = ? WHERE id = ?", auth.hash_password(password), u.id)
	session.destroy_user(u.id)
	print("Password changed for '" .. u.username .. "' (sessions ended).")
	return 0
end

function commands.admin(username)
	if not username then return nil end
	local u = find(username)
	if not u then return 1 end
	dk.db:exec("UPDATE users SET authlevel = 1 WHERE id = ?", u.id)
	print("'" .. u.username .. "' is now an administrator.")
	return 0
end

return {
	run = function(cmd, ...)
		local fn = commands[cmd or ""]
		local rc = fn and fn(...)
		if rc == nil then
			io.stderr:write(USAGE)
			return 2
		end
		return rc
	end,
}
