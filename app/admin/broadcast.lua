-- admin/broadcast.lua :: GET/POST /admin/broadcast: the banner shown at the top of every
-- page (lib/banner.lua), live on open pages, until it is cleared or expires.
local banner = require("lib.banner")
local common = require("admin.common")
local php = require("lib.php")
local view = require("lib.view")

local broadcast = {}

local function form(req, ctx)
	ctx.current = banner.current()
	ctx.max_chars = banner.MAX_CHARS
	return common.page(req, "Broadcast", "admin/broadcast", ctx)
end

function broadcast.show(req)
	return form(req, { saved = req.query.saved, minutes = "" })
end

-- form: text, minutes (empty: until cleared), and the button: set or clear
function broadcast.save(req)
	if req.form.clear ~= nil then
		banner.clear()
		return view.redirect("/admin/broadcast?saved=cleared")
	end
	local text = php.trim(common.field(req, "text")):gsub("[%c]", " ")
	local minutes_s = php.trim(common.field(req, "minutes"))
	local errors = {}
	if text == "" then
		errors[#errors + 1] = "Text is required."
	elseif not utf8.len(text) then
		errors[#errors + 1] = "Text contains invalid characters."
	elseif utf8.len(text) > banner.MAX_CHARS then
		errors[#errors + 1] = "Text must be " .. banner.MAX_CHARS .. " characters or less."
	end
	local minutes
	if minutes_s ~= "" then
		minutes = math.tointeger(tonumber(minutes_s))
		if not minutes or minutes < 1 or minutes > banner.MAX_MINUTES then
			errors[#errors + 1] = "Expires must be a number of minutes from 1 to " .. banner.MAX_MINUTES ..
				", or empty."
		end
	end
	if #errors > 0 then
		return form(req, { errors = errors, text = common.field(req, "text"), minutes = minutes_s })
	end
	banner.set(text, minutes)
	return view.redirect("/admin/broadcast?saved=set")
end

return broadcast
