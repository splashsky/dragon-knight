# tests/e2e/theme.sh :: themes (lib/themes.lua): the default theme's markup on every
# layout, POST /theme (CSRF, the dk_theme cookie, safe return paths, unknown keys), the
# retro theme, and the static font, theme CSS and images. Sourced by tests/run.sh.

theme_is() {  # theme_is KEY: the page in $BODY uses the theme KEY (and only it)
	local other=retro
	[ "$1" = retro ] && other=default
	expect_body "<link rel=\"stylesheet\" href=\"/static/css/themes/$1.css\">"
	expect_no_body "/static/css/themes/$other.css"
}
theme_post() {  # theme_post KEY BACK [CSRF]
	t_post /theme "csrf=${3:-$(t_csrf)}&theme=$1&back=$(t_enc "$2")"
}

t_section "theme: default markup, logged out"
t_jar themeanon; t_reset_jar
t_get /login;      expect_status 200; theme_is default
expect_body '<body class="theme-default">'
expect_body '<a class="dk-logo" href="/"><img src="/static/images/themes/default/logo.png" width="355" height="120" alt="Dragon Knight" title="Dragon Knight"></a>'
expect_no_body 'logo.gif'
expect_body '<form class="theme-picker" method="post" action="/theme">'
expect_body '<input type="hidden" name="back" value="/login" data-r="theme-back">'
expect_body '<b aria-current="true">Default</b>'
expect_body '<button class="link" type="submit" name="theme" value="retro">Retro</button>'
expect_body '/static/fonts/vollkorn/Vollkorn-Regular.ttf'
t_get /help;       expect_status 200; theme_is default
expect_body '<body class="minimal theme-default help">'; expect_body 'src="/static/images/themes/default/logo.png"'
expect_body 'class="theme-picker"'; expect_body 'name="back" value="/help"'
t_get /help/items; theme_is default; expect_body 'src="/static/images/themes/default/logo.png"'
t_get /changelog;  theme_is default; expect_body 'src="/static/images/themes/default/logo.png"'
t_get /no/such/page; expect_status 404; theme_is default; expect_body 'class="theme-default"'

t_section "theme: default markup, logged in"
t_jar themeplayer; t_reset_jar
t_register themer themepw1 themer@example.com Themer; t_login themer themepw1
t_get /;           expect_status 200; theme_is default
expect_body '<body class="theme-default" data-live'; expect_body 'src="/static/images/themes/default/logo.png"'
expect_body 'name="back" value="/"'
t_get /character;  expect_status 200; theme_is default; expect_body '<body class="minimal theme-default" data-live data-csrf="'
t_get /babble;     expect_status 200; theme_is default; expect_body 'name="back" value="/babble"'
t_jar themeadmin; t_reset_jar
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin;      expect_status 200; theme_is default
expect_body '<body class="admin theme-default" data-live'; expect_body 'src="/static/images/themes/default/logo.png"'
expect_body 'class="theme-picker"'; expect_body 'name="back" value="/admin"'
t_get "/admin/users?start=0"; expect_status 200; expect_body 'name="back" value="/admin/users?start=0"'

t_section "theme: static files"
t_get /static/css/dk.css;                 expect_status 200; expect_body '@font-face'
expect_body 'font-family: Vollkorn;'; expect_body 'Vollkorn, Georgia, "Times New Roman", serif'
t_get /static/css/themes/default.css;     expect_status 200; expect_body '/static/images/themes/default/background.jpg'
t_get /static/css/themes/retro.css;       expect_status 200; expect_body '/static/images/themes/retro/background.jpg'
t_get /static/images/themes/default/background.jpg; expect_status 200; expect_header '^content-type: image/jpeg'
t_get /static/images/themes/default/logo.png;       expect_status 200; expect_header '^content-type: image/png'
t_get /static/images/themes/retro/logo.gif;         expect_status 200
t_get /static/images/themes/retro/background.jpg;   expect_status 200
t_get /static/images/themes/retro/town_8.gif;       expect_status 200
t_get /static/images/logo.gif;                      expect_status 404   # moved to the Retro theme
for w in Regular Italic Bold BoldItalic; do
	t_get "/static/fonts/vollkorn/Vollkorn-$w.ttf"; expect_status 200; expect_header '^content-length: [1-9][0-9]{4,}'
done
t_get /static/fonts/vollkorn/OFL.txt;     expect_status 200; expect_body 'SIL OPEN FONT LICENSE'

t_section "theme: POST /theme needs CSRF"
t_jar themeanon
t_get /login
t_post /theme "theme=retro&back=/login";  expect_status 403; expect_no_body 'theme-retro'
grep -qi '^set-cookie: dk_theme=' "$HEADERS" && t_fail "dk_theme set without csrf" || t_ok
theme_post retro /login "$(printf '0%.0s' $(seq 64))"; expect_status 403
t_get /login;      theme_is default

t_section "theme: choose Retro, logged out"
t_get /help
theme_post retro /help
expect_redirect /help
expect_header '^set-cookie: dk_theme=retro; Path=/; Max-Age=31536000; SameSite=Lax'$'\r''?$'
t_get /help;       theme_is retro; expect_body '<body class="minimal theme-retro help">'
expect_body '<a class="dk-logo" href="/"><img src="/static/images/themes/retro/logo.gif" width="409" height="108" alt="Dragon Knight" title="Dragon Knight"></a>'
expect_body '<b aria-current="true">Retro</b>'
expect_body '<button class="link" type="submit" name="theme" value="default">Default</button>'
t_get /login;      theme_is retro; expect_body '<body class="theme-retro">'
expect_body 'src="/static/images/themes/retro/logo.gif"'; expect_no_body 'themes/default/logo.png'
t_get /changelog;  theme_is retro

t_section "theme: return paths"
t_get /login
theme_post retro "/help/items?x=1#top"; expect_redirect '/help/items\?x=1#top'
t_get /login
theme_post retro https://evil.example/;  expect_redirect /
t_get /login
theme_post retro //evil.example/x;       expect_redirect /
t_get /login
theme_post retro '/\evil.example';       expect_redirect /
t_get /login
theme_post retro 'javascript:alert(1)';  expect_redirect /
t_get /login
theme_post retro "$(printf '/help\r\nX-Evil: 1')"; expect_redirect /
grep -qi '^x-evil' "$HEADERS" && t_fail "header injection" || t_ok
t_get /login
theme_post retro /logout;                expect_redirect /     # POST-only route
t_get /login
theme_post retro /no/such/page;          expect_redirect /
t_get /login
t_post /theme "csrf=$(t_csrf)&theme=retro"; expect_redirect /

t_section "theme: unknown keys"
t_get /login
theme_post neon /login;                  expect_status 400
grep -qi '^set-cookie: dk_theme=' "$HEADERS" && t_fail "dk_theme set for an unknown theme" || t_ok
t_get /login
t_post /theme "csrf=$(t_csrf)&back=/login"; expect_status 400
t_get /login;      theme_is retro           # unchanged
t_jar themebogus; t_reset_jar
t_get /login --cookie 'dk_theme=%3Cscript%3E'; expect_status 200; theme_is default; expect_no_body '%3Cscript'
t_jar themeanon

t_section "theme: switch back to Default"
t_get /login
theme_post default /login;               expect_redirect /login
expect_header '^set-cookie: dk_theme=default; Path=/; Max-Age=31536000; SameSite=Lax'
t_get /login;      theme_is default; expect_body '<body class="theme-default">'
expect_body 'src="/static/images/themes/default/logo.png"'

t_section "theme: logged in, kept across login"
t_jar themeplayer
t_get /;           expect_status 200; theme_is default
# Default writes them as text
expect_body '<h1 class="title page-title">Welcome to Midworld</h1>'
# the Location panel: where the player is as its heading, then the coordinates and the map
expect_body '<h2 class="title">In Midworld</h2>'; expect_no_body 'class="loc-where"'
expect_body '<div class="loc-line"><span class="loc-coords" title="Latitude 0N, longitude 0E">0N, 0E</span> &middot; <a href="/map"'
expect_body '<button class="link">Log Out</button></form>'; expect_body '<a href="/help">Help</a>'
expect_no_body 'images/themes/retro/'
theme_post retro /;                      expect_redirect /
t_get /;           expect_status 200; theme_is retro; expect_body '<body class="theme-retro" data-live'
expect_body 'src="/static/images/themes/retro/logo.gif"'
# Retro draws the original's pictures for the headings and top links (lib/themes.lua art)
expect_body '<h2 class="title"><img src="/static/images/themes/retro/button_location.gif" alt="Location" title="Location"></h2>'
expect_body '<div class="loc-where">In Midworld</div>'   # the picture says "Location": where, below it
expect_body '<h1 class="title page-title"><img src="/static/images/themes/retro/town_1.gif" alt="Welcome to Midworld" title="Welcome to Midworld"></h1>'
expect_body '<input type="image" src="/static/images/themes/retro/button_logout.gif" alt="Log Out" title="Log Out">'
expect_body '<a href="/help"><img src="/static/images/themes/retro/button_help.gif" alt="Help" title="Help"></a>'
expect_body '<h2 class="title">Latest News</h2>'   # no picture: text
t_get /character;  theme_is retro; expect_body '<body class="minimal theme-retro" data-live data-csrf="'
t_logout
t_get /login;      theme_is retro
t_login themer themepw1; t_get /; theme_is retro
t_jar themeadmin
t_get /admin
theme_post retro /admin;                 expect_redirect /admin
t_get /admin;      theme_is retro; expect_body '<body class="admin theme-retro" data-live'; expect_body 'src="/static/images/themes/retro/logo.gif"'
theme_post default /admin;               expect_redirect /admin
t_get /admin;      theme_is default
