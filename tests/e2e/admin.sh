# tests/e2e/admin.sh :: admin control panel. Sourced by tests/run.sh.
# Everything this script changes in game data is snapshotted first and restored at the end
# (admin.sh runs before the other feature scripts).

admin_eq() {  # admin_eq "SQL" expected label
	local got
	got=$(t_sql "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: expected '$2', got '$got'"; fi
}
adm_body() {  # adm_body text   (like expect_body, with the body's lines joined)
	if tr -d '\n' < "$BODY" | grep -qF -- "$1"; then t_ok; else t_fail "body lacks: $1"; fi
}

if ! t_has_sql; then
	echo "admin.sh: skipped (needs sqlite3 or python3)"
else

t_sql "CREATE TABLE adm_snap_control AS SELECT * FROM control;
			 CREATE TABLE adm_snap_items AS SELECT * FROM items WHERE id = 1;
			 CREATE TABLE adm_snap_drops AS SELECT * FROM drops WHERE id = 1;
			 CREATE TABLE adm_snap_towns AS SELECT * FROM towns WHERE id = 2;
			 CREATE TABLE adm_snap_monsters AS SELECT * FROM monsters WHERE id = 1;
			 CREATE TABLE adm_snap_spells AS SELECT * FROM spells WHERE id = 1;"
ADM_NEWS_MAX=$(t_sql "SELECT coalesce(max(id), 0) FROM news")
ADM_FORUM_MAX=$(t_sql "SELECT coalesce(max(id), 0) FROM forum")

t_section "admin: access"
t_jar admanon
t_get /admin;              expect_status 403; expect_body 'Please log in to the <a href="/login">game</a> before using the control panel.'
t_get /admin/users/1;      expect_status 403
t_jar admtester
t_register admtester playerpw1 admtester@example.com AdmTester
t_login admtester playerpw1
t_get /admin;              expect_status 403; expect_body 'You must have administrator privileges to use the control panel.'
t_get /admin/settings;     expect_status 403
t_get /changepassword
t_post /admin/settings "csrf=$(t_csrf)&gamename=Pwned&gamesize=250"
expect_status 403
admin_eq "SELECT gamename FROM control" "Dragon Knight" "non-admin settings post"
t_get /;                   expect_no_body 'href="/admin"'

t_jar admadmin
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin;              expect_status 200; expect_body 'Welcome to the Dragon Knight Administration section.'
expect_body 'href="/admin/settings"'; expect_body 'href="/admin/classes"'; expect_body '<a href="/">Game Home</a>'
expect_body '<title>Admin Home</title>'; expect_body 'Queries'

t_section "admin: csrf"
t_post /admin/items/1 "name=NoToken&type=1&buycost=1&attribute=1&special=X"
expect_status 403
t_post /admin/news "csrf=$(printf 'a%.0s' $(seq 64))&content=forged"
expect_status 403
admin_eq "SELECT name FROM items WHERE id = 1" "Stick" "item untouched without csrf"
admin_eq "SELECT count(*) FROM news WHERE content = 'forged'" "0" "news untouched without csrf"

t_section "admin: settings"
t_get /admin/settings;     expect_status 200; expect_body 'Main Settings'; expect_body 'name="gamesize" size="3" maxlength="3" value="250"'
expect_no_body 'name="class1name"'; expect_no_body 'name="diff'; expect_no_body 'Difficulty'
expect_no_body 'name="compression"'
t_form_submit /admin/settings gamename= gamesize=252 forumtype=2 forumaddress=
expect_status 200
expect_body 'Game name is required.'; expect_body 'Map size must be divisible by five.'
expect_body 'You must specify a forum address when using the External setting.'
expect_no_body 'Map size must be a number.'
t_form_submit /admin/settings gamesize=abc
expect_body 'Map size must be a number.'; expect_no_body 'divisible by five'
t_form_submit /admin/settings forumtype=7
expect_body 'Forum Type is invalid.'
admin_eq "SELECT gamename || '|' || gamesize FROM control" "Dragon Knight|250" "invalid settings not saved"

t_get /admin/settings
t_form_submit /admin/settings "gamename=Realm <&> Test" gameopen=0 gamesize=200 class1name=Sorcerer \
	shownews=1 compression=1 id=5 bogus=1
expect_redirect '/admin/settings\?saved=1'
t_get '/admin/settings?saved=1'; expect_body 'Settings updated.'
expect_body 'value="Realm &lt;&amp;&gt; Test"'; expect_body 'name="gamesize" size="3" maxlength="3" value="200"'
admin_eq "SELECT id || '|' || gamename || '|' || gameopen || '|' || gamesize || '|' || shownews || '|' || compression FROM control" \
	"1|Realm <&> Test|0|200|1|1" "settings saved (compression untouched)"
admin_eq "SELECT typeof(gamesize) || typeof(gameopen) || typeof(gamename) FROM control" "integerintegertext" "settings types"
admin_eq "SELECT name FROM classes WHERE id = 1" "Mage" "no class names in the settings"
t_get /login;              expect_body 'alt="Realm &lt;&amp;&gt; Test"'
t_jar admtester
t_get /;                   expect_body 'The game is currently closed for maintanence.'
t_jar admadmin
t_get /admin;              expect_status 200   # admin works while the game is closed
t_get /admin/monsters
expect_body 'Highest monster level should be 40, yours is 50.'
t_get /admin/settings
t_form_submit /admin/settings gameopen=1 gamesize=250
t_jar admtester
t_get /;                   expect_no_body 'The game is currently closed'
t_jar admadmin
t_get /admin/monsters;     expect_body 'Monster level and map size match.'

t_section "admin: items"
t_get /admin/items;        expect_status 200; expect_body '<a href="/admin/items/1">Stick</a>'
t_get /admin/items/1;      expect_body 'Special Codes:'; expect_body 'value="Stick"'
t_form_submit /admin/items/1 buycost= attribute=1x type=9
expect_body 'Cost is required.'; expect_body 'Cost must be a number.'; expect_body 'Attribute must be a number.'
expect_body 'Type is invalid.'
t_form_submit /admin/items/1 name= buycost=5
expect_body 'Name is required.'
t_get /admin/items/1
t_form_submit /admin/items/1 "name=<script>alert(1)</script>" type=2 buycost=123 attribute=7.5 "special= " \
	id=999 password=x unknowncol=1 "name2=y"
expect_redirect '/admin/items/1\?saved=1'
t_get /admin/items/1?saved=1; expect_body 'Item updated.'
admin_eq "SELECT id || '|' || name || '|' || type || '|' || buycost || '|' || attribute || '|' || special FROM items WHERE id = 1" \
	"1|<script>alert(1)</script>|2|123|8|X" "item saved"
admin_eq "SELECT count(*) FROM items WHERE id = 999" "0" "no mass-assigned id"
t_get /admin/items;        expect_body '&lt;script&gt;alert(1)&lt;/script&gt;'; expect_no_body '<script>alert'
t_get /admin/items/1;      expect_body 'value="&lt;script&gt;alert(1)&lt;/script&gt;"'
t_get /admin/items/9999;   expect_status 404
t_get /admin/items/abc;    expect_status 404

t_section "admin: drops"
t_get /admin/drops;        expect_body '<a href="/admin/drops/1">Life Pebble</a>'
t_get /admin/drops/1
t_form_submit /admin/drops/1 attribute1=X mlevel=
expect_body 'First attribute is required.'; expect_body 'Monster level is required.'; expect_body 'Monster level must be a number.'
t_form_submit /admin/drops/1 name=Pebble2 mlevel=3 attribute1=maxhp,20 "attribute2="
expect_redirect '/admin/drops/1\?saved=1'
admin_eq "SELECT name || '|' || mlevel || '|' || attribute1 || '|' || attribute2 FROM drops WHERE id = 1" \
	"Pebble2|3|maxhp,20|X" "drop saved"

t_section "admin: towns"
t_get /admin/towns/2;      expect_body 'Items List:'
t_form_submit /admin/towns/2 itemslist= latitude=north
expect_body 'Items List is required.'; expect_body 'Latitude must be a number.'
t_form_submit /admin/towns/2 name=Newtown latitude=-31 longitude=44 innprice=11 mapprice=22 travelpoints=3 itemslist=1,2,3
expect_redirect '/admin/towns/2\?saved=1'
admin_eq "SELECT name || '|' || latitude || '|' || longitude || '|' || innprice || '|' || mapprice || '|' || travelpoints || '|' || itemslist FROM towns WHERE id = 2" \
	"Newtown|-31|44|11|22|3|1,2,3" "town saved"

t_section "admin: monsters"
t_get /admin/monsters/1;   expect_body 'Immunity:'
t_form_submit /admin/monsters/1 maxhp= maxexp=lots
expect_body 'Max HP is required.'; expect_body 'Max HP must be a number.'; expect_body 'Max Exp must be a number.'
t_form_submit /admin/monsters/1 name=Slimer maxhp=1.6 maxdam=9 armor=2 level=1 maxexp=3 maxgold=4 immune=2
expect_redirect '/admin/monsters/1\?saved=1'
admin_eq "SELECT name || '|' || maxhp || '|' || maxdam || '|' || immune FROM monsters WHERE id = 1" \
	"Slimer|2|9|2" "monster saved"
t_get /admin/monsters/1;   expect_body '<option value="2" selected>Hurt &amp; Sleep Spells</option>'

t_section "admin: spells"
t_get /admin/spells/1
t_form_submit /admin/spells/1 mp=
expect_body 'MP is required.'; expect_body 'MP must be a number.'
t_form_submit /admin/spells/1 name=Mend mp=4 attribute=12 type=4
expect_redirect '/admin/spells/1\?saved=1'
admin_eq "SELECT name || '|' || mp || '|' || attribute || '|' || type FROM spells WHERE id = 1" \
	"Mend|4|12|4" "spell saved"

t_section "admin: classes"
# class files app/content/classes/*.lua; admins override some fields (tests/e2e/content.sh
# covers the files themselves)
t_get /admin/levels;       expect_redirect /admin/classes
t_get /admin/classes;      expect_status 200; expect_body '<a href="/admin/classes/1">Mage</a>'
expect_body '<a href="/admin/classes/3">Paladin</a>'; expect_body 'The database is in sync with the content files.'
expect_body 'classes: 3 files, 3 in the database (0 retired), 0 overrides.'
t_get /admin/classes/2;    expect_status 200; expect_body 'Edit Class: Warrior'
expect_body 'name="name" size="30" value="Warrior"'; expect_body 'app/content/classes/warrior.lua'
expect_body '<option value="1" selected>Yes</option>'; expect_body 'name="start_hp" size="6" value="15"'
expect_body '<textarea name="description" rows="6" cols="40">Medium level-ups'
# experience and level gains are read-only (level 2: exp 18, HP 2, bonus 0, MP 4, TP 1,
# strength 2, dexterity 1, Heal; level 10: the milestone bonus)
expect_body 'Experience base 18, stages 2x2,1.5x8,1.25x5,1.125x27'
expect_body "<tr><td>2</td><td>18</td><td>2</td><td>0</td><td>4</td><td>1</td><td>2</td><td>1</td><td>$(t_sql "SELECT name FROM spells WHERE id = 1")</td></tr>"
expect_body '<tr><td>10</td><td>2,368</td><td>0</td><td>10</td>'
expect_no_body 'name="exp_base"'; expect_no_body 'name="levels'
t_get /admin/classes/99;   expect_status 404
t_post /admin/classes/2 "name=NoToken"; expect_status 403
adm_class_post() {  # adm_class_post ID 'field=value&...' (other fields: the current values)
	local id=$1 over=$2 data f v
	t_get "/admin/classes/$id"
	data="csrf=$(t_csrf)"
	for f in name description sort playable start_hp start_mp start_tp start_strength start_dexterity; do
		case "&$over" in *"&$f="*) continue ;; esac
		v=$(t_sql "SELECT $f FROM classes WHERE id = $id")
		data+="&$f=$(t_enc "$v")"
	done
	t_post "/admin/classes/$id" "$data&$over"
}
adm_class_post 2 "name=&playable=7&start_hp=0&start_tp=x"
expect_status 200
expect_body 'Name must be a one-line string of at most 50 characters, not empty.'
expect_body 'Playable must be 0 or 1.'; expect_body 'Starting HP must be an integer from 1 to 100000.'
expect_body 'Starting TP must be an integer from 0 to 100000.'
admin_eq "SELECT count(*) FROM content_overrides" "0" "invalid class form not saved"
adm_class_post 2 "name=$(t_enc 'Fighter <b>')&playable=0&start_hp=20&id=7&exp_base=1&key=x"
expect_redirect '/admin/classes/2\?saved=1'
admin_eq "SELECT id || '|' || key || '|' || name || '|' || playable || '|' || start_hp || '|' || exp_base FROM classes WHERE id = 2" \
	"2|warrior|Fighter <b>|0|20|18" "class overrides applied"
admin_eq "SELECT group_concat(field || '=' || value, ';') FROM (SELECT * FROM content_overrides WHERE kind = 'classes' AND key = 'warrior' ORDER BY field)" \
	"name=Fighter <b>;playable=0;start_hp=20" "only the changed fields are overridden"
t_get '/admin/classes/2?saved=1'; expect_body 'Class updated.'; expect_body 'File value: Warrior'
expect_body 'value="Fighter &lt;b&gt;"'; expect_body 'Reset Name to file'; expect_no_body 'Reset Description to file'
t_get /admin/classes;      expect_body 'Fighter &lt;b&gt;</a>'
t_jar admreg; t_get /register
expect_no_body 'Fighter'; expect_body '<option value="1">Mage</option>'; expect_body '<option value="3">Paladin</option>'
t_register admwarrior pw1 admwarrior@example.com AdmWarrior 2
expect_body 'Character Class is invalid.'
t_jar admadmin
adm_class_post 2 "playable=1"
t_jar admreg
t_register admwarrior pw1 admwarrior@example.com AdmWarrior 2
expect_body 'Your account was created succesfully'
admin_eq "SELECT charclass || '|' || currenthp || '|' || maxhp || '|' || maxmp || '|' || maxtp || '|' || strength || '|' || attackpower FROM users WHERE username = 'admwarrior'" \
	"2|20|20|0|10|5|5" "new character gets the overridden starting stats"
t_login admwarrior pw1
t_get /character;          expect_body 'Class: Fighter &lt;b&gt;'
t_jar admadmin
# overrides survive a sync
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
grep -qF 'Content synced (classes: 3, 0 new, 0 retired).' "$T/content.log" && t_ok || t_fail "sync output: $(cat "$T/content.log")"
admin_eq "SELECT name || '|' || start_hp FROM classes WHERE id = 2" "Fighter <b>|20" "overrides survive a sync"
t_get /admin/classes/2
t_post /admin/classes/2/reset "csrf=$(t_csrf)&field=name"
expect_redirect '/admin/classes/2\?saved=1'
admin_eq "SELECT name || '|' || start_hp FROM classes WHERE id = 2" "Warrior|20" "name reset to file"
t_get /admin/classes/2
t_post /admin/classes/2/reset "csrf=$(t_csrf)&field=*"
admin_eq "SELECT name || '|' || start_hp || '|' || playable FROM classes WHERE id = 2" "Warrior|15|1" "all reset to file"
admin_eq "SELECT count(*) FROM content_overrides" "0" "no overrides left"
t_sql "DELETE FROM users WHERE username = 'admwarrior'"

t_section "admin: users"
ADM_UID=$(t_sql "SELECT id FROM users WHERE username = 'admtester'")
ADM_HASH=$(t_sql "SELECT password FROM users WHERE id = $ADM_UID")
t_get /admin/users;        expect_body "<a href=\"/admin/users/$ADM_UID\">admtester</a>"
t_get /admin/users/$ADM_UID; expect_body 'Username:'; expect_body 'Current Monster Sleep:'; expect_no_body 'pbkdf2$'
expect_body 'name="charclass"'; expect_no_body 'name="difficulty"'
expect_body '<option value="2">Warrior</option>'; expect_body '<option value="1" selected>Mage</option>'
t_form_submit /admin/users/$ADM_UID email= gold=lots
expect_body 'Email is required.'; expect_body 'Gold must be a number.'
t_get /admin/users/$ADM_UID
t_form_submit /admin/users/$ADM_UID "charname=<i>Hero</i>" gold=5000 level=7 authlevel=2 currentaction=Exploring \
	spells=0,1,2 username=evil password=plain regdate=1 id=4242 onlinetime=3
expect_redirect "/admin/users/$ADM_UID\\?saved=1"
admin_eq "SELECT username || '|' || charname || '|' || gold || '|' || level || '|' || authlevel || '|' || currentaction || '|' || spells || '|' || (regdate > 1) FROM users WHERE id = $ADM_UID" \
	"admtester|<i>Hero</i>|5000|7|2|Exploring|0,1,2|1" "user saved"
admin_eq "SELECT password FROM users WHERE id = $ADM_UID" "$ADM_HASH" "password not mass-assigned"
admin_eq "SELECT count(*) FROM users WHERE id = 4242" "0" "user id not mass-assigned"
t_jar admtester
t_get /;                   expect_status 403; expect_body 'Your account has been blocked.'
t_jar admadmin
t_get /admin/users/$ADM_UID
t_form_submit /admin/users/$ADM_UID authlevel=0 newpassword=brandnew9
expect_redirect "/admin/users/$ADM_UID\\?saved=1"
t_jar admtester
t_get /;                   expect_redirect /login   # sessions ended by the password reset
t_login admtester playerpw1; expect_body 'Invalid username or password'
t_login admtester brandnew9; expect_redirect /
t_jar admadmin
t_get /admin;              expect_status 200       # the admin's own session survives

t_section "admin: users paging"
t_sql "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 120)
			 INSERT INTO users (username, email, charname) SELECT 'admbulk' || i, 'admbulk' || i || '@example.com', 'AdmBulk' || i FROM n;
			 UPDATE users SET username = '<b>bold</b>' WHERE username = 'admbulk1';"
t_get /admin/users;        expect_body 'Next &raquo;'; expect_body 'href="/admin/users?start=100"'; expect_no_body 'Previous'
expect_body '&lt;b&gt;bold&lt;/b&gt;'; expect_no_body '<b>bold</b>'
t_get '/admin/users?start=100'; expect_body 'Showing 101'; expect_body '&laquo; Previous'
t_sql "DELETE FROM users WHERE username LIKE 'admbulk%' OR username = '<b>bold</b>'"

t_section "admin: news"
t_get /admin/news;         expect_body 'Add A News Post'; expect_body 'name="title" size="50" maxlength="100" value=""'
t_post /admin/news "csrf=$(t_csrf)&content="
expect_body 'Content is required.'
t_post /admin/news "csrf=$(t_csrf)&title=$(t_enc '<i>kept</i>')&content=+%0D%0A+"
expect_body 'Content is required.'; expect_body 'name="title" size="50" maxlength="100" value="&lt;i&gt;kept&lt;/i&gt;"'
t_post /admin/news "csrf=$(t_csrf)&title=$(printf 'y%.0s' $(seq 101))&content=x"
expect_body 'Title must be 100 characters or less.'
admin_eq "SELECT count(*) FROM news WHERE id > $ADM_NEWS_MAX" "0" "invalid news not saved"
t_post /admin/news "csrf=$(t_csrf)&submit=Submit&title=&content=$(t_enc 'Fresh <b>news</b> from the admin')"
expect_redirect '/admin/news\?saved=1'
t_get /admin/news?saved=1; expect_body 'News post added.'
ADM_ADMIN_ID=$(t_sql "SELECT id FROM users WHERE username = '$ADMIN_USER'")
admin_eq "SELECT content || '|' || title || '|' || author_id || '|' || (abs(postdate - strftime('%s','now')) < 60) FROM news ORDER BY id DESC LIMIT 1" \
	"Fresh <b>news</b> from the admin|Fresh <b>news</b> from the admin|$ADM_ADMIN_ID|1" "news saved"
admin_eq "SELECT f.board || '|' || f.author || '|' || (f.title = n.title) FROM news n JOIN forum f ON f.id = n.thread_id ORDER BY n.id DESC LIMIT 1" \
	"2|Admin|1" "news thread"
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 WHERE id = $ADM_UID"
t_jar admtester
t_get /;                   expect_body 'Fresh &lt;b&gt;news&lt;/b&gt; from the admin'

# restore everything this script touched
t_sql "DELETE FROM control; INSERT INTO control SELECT * FROM adm_snap_control; DROP TABLE adm_snap_control;
			 DELETE FROM items WHERE id = 1; INSERT INTO items SELECT * FROM adm_snap_items; DROP TABLE adm_snap_items;
			 DELETE FROM drops WHERE id = 1; INSERT INTO drops SELECT * FROM adm_snap_drops; DROP TABLE adm_snap_drops;
			 DELETE FROM towns WHERE id = 2; INSERT INTO towns SELECT * FROM adm_snap_towns; DROP TABLE adm_snap_towns;
			 DELETE FROM monsters WHERE id = 1; INSERT INTO monsters SELECT * FROM adm_snap_monsters; DROP TABLE adm_snap_monsters;
			 DELETE FROM spells WHERE id = 1; INSERT INTO spells SELECT * FROM adm_snap_spells; DROP TABLE adm_snap_spells;
			 DELETE FROM news WHERE id > $ADM_NEWS_MAX; DELETE FROM forum WHERE id > $ADM_FORUM_MAX;"
fi
