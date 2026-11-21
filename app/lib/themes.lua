-- themes.lua :: the site themes. A theme is a stylesheet (public/css/themes/<key>.css,
-- linked after dk.css and the feature stylesheets: it only overrides), a logo and,
-- optionally, art: pictures for the layout's labels (the panels' headings, the page
-- titles, the top links; see view.lua's art helper), drawn instead of their text.
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
		logo = { src = "/static/images/themes/retro/logo.gif", width = 409, height = 108, alt = "Dragon Knight" },
		-- the original's pictures (public/images/themes/retro/<file>); button_towns.gif and
		-- button_functions.gif headed the panels 3.1 replaced (the header's links, Travel)
		art = {
			location = "button_location.gif",
			character = "button_character.gif", inventory = "button_inventory.gif",
			fastspells = "button_fastspells.gif", spells = "button_spells.gif",
			exploring = "title_exploring.gif", fighting = "title_fighting.gif",
			login = "button_login.gif", logout = "button_logout.gif", register = "button_register.gif",
			help = "button_help.gif",
			town_1 = "town_1.gif", town_2 = "town_2.gif", town_3 = "town_3.gif", town_4 = "town_4.gif",
			town_5 = "town_5.gif", town_6 = "town_6.gif", town_7 = "town_7.gif", town_8 = "town_8.gif",
		},
		art_dir = "/static/images/themes/retro/",
	},
}

local by_key = {}
for _, t in ipairs(themes.list) do by_key[t.key] = t end

-- The theme with this key, or nil.
function themes.get(key)
	if type(key) ~= "string" then return nil end
	return by_key[key]
end

-- The URL of the theme's picture for label `key`, or nil (the label is text).
function themes.art(theme, key)
	local file = theme.art and theme.art[key]
	return file and (theme.art_dir .. file) or nil
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
