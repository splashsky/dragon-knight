-- themes.lua :: the site themes. A theme is a stylesheet (public/css/themes/<key>.css,
-- linked after dk.css and the feature stylesheets: it only overrides) and a logo.
-- The choice is the dk_theme cookie (POST /theme, routes/community.lua); no cookie or an
-- unknown key means themes.DEFAULT. Pure: no database access (the 500/503 pages use it).
local themes = {}

themes.COOKIE = "dk_theme"
themes.DEFAULT = "default"
themes.MAX_AGE = 365 * 24 * 3600

-- In the order the theme selector lists them.
themes.list = {
	{
		key = "default",
		name = "Default",
		stylesheet = "/static/css/themes/default.css",
		logo = { src = "/static/images/themes/default/logo.png", width = 355, height = 120, alt = "Dragon Knight" },
	},
	{
		key = "retro",
		name = "Retro",
		stylesheet = "/static/css/themes/retro.css",
		logo = { src = "/static/images/logo.gif", width = 409, height = 108, alt = "Dragon Knight" },
	},
}

local by_key = {}
for _, t in ipairs(themes.list) do by_key[t.key] = t end

-- The theme with this key, or nil.
function themes.get(key)
	if type(key) ~= "string" then return nil end
	return by_key[key]
end

-- The request's theme (from its cookie), else the default theme.
function themes.current(req)
	local cookies = req and req.cookies
	return themes.get(cookies and cookies[themes.COOKIE]) or by_key[themes.DEFAULT]
end

-- s if it is a same-site path ("/x?y"), else nil: no scheme, host, "//" or "/\",
-- control characters or spaces.
function themes.safe_path(s)
	if type(s) ~= "string" or #s > 2000 then return nil end
	if s:sub(1, 1) ~= "/" or s:find("^/[/\\]") then return nil end
	if s:find("[%c%s\\]") then return nil end
	return s
end

return themes
