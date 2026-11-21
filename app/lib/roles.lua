-- roles.lua :: who may do what (docs/APP.md "Roles"). An account's role is users.authlevel
-- (the legacy column and values, plus Moderator in 3.1): 0 a player, 1 an administrator
-- (the control panel, everything a moderator may), 2 blocked (can't play: lib/auth.lua),
-- 3 a moderator (moderates the Babble Box: deletes messages). Pure: no database access.
local roles = {}

roles.PLAYER, roles.ADMIN, roles.BLOCKED, roles.MODERATOR = 0, 1, 2, 3

local NAMES = { [0] = "player", [1] = "admin", [2] = "blocked", [3] = "moderator" }

-- The role's name for an authlevel: "player", "admin", "blocked" or "moderator" (an
-- unknown level is a player's).
function roles.name(level)
	return NAMES[level] or "player"
end

-- The admin panel's choices, in its order: { level, label }.
roles.CHOICES = { { 0, "User" }, { 3, "Moderator" }, { 1, "Admin" }, { 2, "Blocked" } }

function roles.is_admin(user)
	return user ~= nil and user.authlevel == roles.ADMIN
end

-- Whether `user` moderates: deletes Babble Box messages (administrators and moderators).
function roles.can_moderate(user)
	return user ~= nil and (user.authlevel == roles.ADMIN or user.authlevel == roles.MODERATOR)
end

function roles.is_blocked(user)
	return user ~= nil and user.authlevel == roles.BLOCKED
end

return roles
