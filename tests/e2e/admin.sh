# tests/e2e/admin.sh :: admin control panel. Sourced by tests/run.sh.
# Everything this script changes in game data is snapshotted first and restored at the end
# (admin.sh runs before the other feature scripts).

admin_eq() {  # admin_eq "SQL" expected label
	local got
	got=$(t_sql "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: expected '$2', got '$got'"; fi
}

if ! t_has_sql; then
	echo "admin.sh: skipped (needs sqlite3 or python3)"
else

t_sql "CREATE TABLE adm_snap_control AS SELECT * FROM control;
			 CREATE TABLE adm_snap_items AS SELECT * FROM items WHERE id = 1;
			 CREATE TABLE adm_snap_drops AS SELECT * FROM drops WHERE id = 1;
			 CREATE TABLE adm_snap_towns AS SELECT * FROM towns WHERE id = 2;
			 CREATE TABLE adm_snap_monsters AS SELECT * FROM monsters WHERE id = 1;
			 CREATE TABLE adm_snap_spells AS SELECT * FROM spells WHERE id = 1;
			 CREATE TABLE adm_snap_levels AS SELECT * FROM levels WHERE id = 5;"
ADM_NEWS_MAX=$(t_sql "SELECT coalesce(max(id), 0) FROM news")

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
expect_body 'href="/admin/settings"'; expect_body 'href="/admin/levels"'; expect_body '<a href="/">Game Home</a>'
expect_body '<title>Admin Home</title>'; expect_body 'Queries'

t_section "admin: csrf"
t_post /admin/items/1 "name=NoToken&type=1&buycost=1&attribute=1&special=X"
expect_status 403
t_post /admin/news "csrf=$(printf 'a%.0s' $(seq 64))&content=forged"
expect_status 403
admin_eq "SELECT name FROM items WHERE id = 1" "Stick" "item untouched without csrf"
admin_eq "SELECT count(*) FROM news WHERE content = 'forged'" "0" "news untouched without csrf"

t_section "admin: settings"
t_get /admin/settings;     expect_status 200; expect_body 'Main Settings'; expect_body 'name="diff2mod" size="3" maxlength="3" value="1.2"'
expect_no_body 'name="compression"'
t_form_submit /admin/settings gamename= gamesize=252 forumtype=2 forumaddress= class2name= diff3name= diff2mod= diff3mod=abc
expect_status 200
expect_body 'Game name is required.'; expect_body 'Map size must be divisible by five.'
expect_body 'You must specify a forum address when using the External setting.'
expect_body 'Class 2 name is required.'; expect_body 'Difficulty 3 name is required.'
expect_body 'Difficulty 2 value is required.'; expect_body 'Difficulty 3 value must be a number.'
expect_no_body 'Map size must be a number.'
t_form_submit /admin/settings gamesize=abc
expect_body 'Map size must be a number.'; expect_no_body 'divisible by five'
t_form_submit /admin/settings forumtype=7
expect_body 'Forum Type is invalid.'
admin_eq "SELECT gamename || '|' || gamesize FROM control" "Dragon Knight|250" "invalid settings not saved"

t_get /admin/settings
t_form_submit /admin/settings "gamename=Realm <&> Test" gameopen=0 gamesize=200 diff2mod=1.3 diff3mod=2 \
	shownews=1 compression=1 id=5 bogus=1
expect_redirect '/admin/settings\?saved=1'
t_get '/admin/settings?saved=1'; expect_body 'Settings updated.'
expect_body 'value="Realm &lt;&amp;&gt; Test"'; expect_body 'name="diff3mod" size="3" maxlength="3" value="2"'
admin_eq "SELECT id || '|' || gamename || '|' || gameopen || '|' || gamesize || '|' || diff2mod || '|' || diff3mod || '|' || compression FROM control" \
	"1|Realm <&> Test|0|200|1.3|2.0|1" "settings saved (compression untouched)"
admin_eq "SELECT typeof(diff2mod) || typeof(gamesize) FROM control" "realinteger" "settings types"
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

t_section "admin: levels"
t_get /admin/levels;       expect_body '<option value="2">2</option>'; expect_body '<option value="99">99</option>'
expect_no_body '<option value="1">1</option>'; expect_no_body '<option value="100">100</option>'
t_get '/admin/levels?level=5'; expect_redirect /admin/levels/5
t_get /admin/levels/5;     expect_body 'Mage Experience:'; expect_body 'Paladin Spells:'
t_form_submit /admin/levels/5 one_hp= two_exp=lots
expect_body 'Class 1 HP is required.'; expect_body 'Class 1 HP must be a number.'
expect_body 'Class 2 Experience must be a number.'
t_get /admin/levels/5
t_form_submit /admin/levels/5 one_exp=111 two_hp=22 three_spells=7 '1_mp=99' "id=6"
expect_redirect '/admin/levels/5\?saved=1'
admin_eq "SELECT \"1_exp\" || '|' || \"2_hp\" || '|' || \"3_spells\" FROM levels WHERE id = 5" "111|22|7" "level saved"
admin_eq "SELECT \"1_mp\" FROM levels WHERE id = 5" "$(t_sql 'SELECT "1_mp" FROM adm_snap_levels')" "level column not mass-assigned"
t_get /admin/levels/5?saved=1; expect_body 'Level updated.'
t_get /admin/levels/1000;  expect_status 404; expect_body 'No level to edit.'

t_section "admin: users"
ADM_UID=$(t_sql "SELECT id FROM users WHERE username = 'admtester'")
ADM_HASH=$(t_sql "SELECT password FROM users WHERE id = $ADM_UID")
t_get /admin/users;        expect_body "<a href=\"/admin/users/$ADM_UID\">admtester</a>"
t_get /admin/users/$ADM_UID; expect_body 'Username:'; expect_body 'Current Monster Sleep:'; expect_no_body 'pbkdf2$'
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
t_get /admin/news;         expect_body 'Add A News Post'
t_post /admin/news "csrf=$(t_csrf)&content="
expect_body 'Content is required.'
t_post /admin/news "csrf=$(t_csrf)&submit=Submit&content=$(t_enc 'Fresh <b>news</b> from the admin')"
expect_redirect '/admin/news\?saved=1'
t_get /admin/news?saved=1; expect_body 'News post added.'
admin_eq "SELECT content || '|' || (abs(postdate - strftime('%s','now')) < 60) FROM news ORDER BY id DESC LIMIT 1" \
	"Fresh <b>news</b> from the admin|1" "news saved"
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
			 DELETE FROM levels WHERE id = 5; INSERT INTO levels SELECT * FROM adm_snap_levels; DROP TABLE adm_snap_levels;
			 DELETE FROM news WHERE id > $ADM_NEWS_MAX;"
fi
