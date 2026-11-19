-- routes/theme.lua :: POST /theme: choose the site theme (lib/themes.lua), logged in or
-- out. Sets the dk_theme cookie and goes back to the page the selector was on.
local cookie = require("lib.cookie")
local themes = require("lib.themes")
local view = require("lib.view")

-- The selector's page, when it is a same-site path with a GET route; else "/".
local function back_to(req)
	local back = themes.safe_path(req.form.back)
	if not back then return "/" end
	if not require("routes"):match("GET", back:match("^[^?#]*")) then return "/" end
	return back
end

local function choose(req)
	local theme = themes.get(req.form.theme)
	if not theme then
		return view.error(req, 400, "Error", "That theme doesn't exist. Please go back and try again.")
	end
	cookie.set(req, themes.COOKIE, theme.key, { max_age = themes.MAX_AGE, httponly = false })
	return view.redirect(back_to(req))
end

return function(r)
	r:post("/theme", choose)
end
