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
			 CREATE TABLE adm_snap_towns AS SELECT * FROM towns WHERE id = 2;
			 CREATE TABLE adm_snap_town_items AS SELECT * FROM town_items WHERE town_id = 2;
			 CREATE TABLE adm_snap_town_maps AS SELECT * FROM town_maps WHERE town_id = 2;"
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
t_post /admin/items/1 "name=NoToken&price=1&attack=1"
expect_status 403
t_post /admin/news "csrf=$(printf 'a%.0s' $(seq 64))&content=forged"
expect_status 403
admin_eq "SELECT name || '|' || (SELECT count(*) FROM content_overrides) FROM items WHERE id = 1" "Stick|0" "item untouched without csrf"
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

t_section "admin: towns"
t_get /admin/towns/2;      expect_body 'Items:'
expect_body 'name="items" size="60" maxlength="2000" value="branch, club, dagger, clothes, leather_armor, buckler, herb, potion, ether, antidote, '
expect_body ', spark_rod, '   # (and the 3.1 wares: schema 19)
expect_body 'name="maps" size="60" maxlength="2000" value="Midworld, Bris"'   # its neighbours' maps (schema 18)
t_form_submit /admin/towns/2 "items=stick, nope" latitude=north "maps=Midworld, Atlantis"
expect_body "Items: there is no item &#39;nope&#39;."; expect_body 'Latitude must be a number.'
expect_body "Maps: there is no town &#39;Atlantis&#39;."
admin_eq "SELECT group_concat(item_key) FROM (SELECT item_key FROM town_items WHERE town_id = 2 ORDER BY item_key)" \
	"$(t_sql "SELECT group_concat(item_key) FROM (SELECT item_key FROM adm_snap_town_items ORDER BY item_key)")" "invalid town not saved"
t_get /admin/towns/2
t_form_submit /admin/towns/2 name=Newtown latitude=-31 longitude=44 innprice=11 mapprice=22 travelpoints=3 "items=herb,stick  club" \
	"maps=kalle, Roma ,Endworld"   # (any case; its own name, Roma before this save, left out)
expect_redirect '/admin/towns/2\?saved=1'
admin_eq "SELECT name || '|' || latitude || '|' || longitude || '|' || innprice || '|' || mapprice || '|' || travelpoints FROM towns WHERE id = 2" \
	"Newtown|-31|44|11|22|3" "town saved"
admin_eq "SELECT group_concat(item_key) FROM (SELECT item_key FROM town_items WHERE town_id = 2 ORDER BY item_key)" "club,herb,stick" "shop list saved (by key)"
admin_eq "SELECT group_concat(map_id) FROM (SELECT map_id FROM town_maps WHERE town_id = 2 ORDER BY map_id)" "4,8" "maps saved"
t_get /admin/towns/2;      expect_body 'name="items" size="60" maxlength="2000" value="stick, club, herb"'
expect_body 'name="maps" size="60" maxlength="2000" value="Kalle, Endworld"'

t_section "admin: monsters"
# monster files app/content/monsters/*.lua; admins override the stats, MP, uses_mp, the
# attack's weight, roams, the attack's element, resistances and wards; the loadout is the
# file's (read-only here)
t_get /admin/monsters;     expect_status 200; expect_body '<a href="/admin/monsters/1">Blue Slime</a>'
expect_body '<td>blue_slime</td><td>1</td><td>4</td><td>3</td><td>1</td><td>5</td><td>1</td>'
expect_body 'monsters: 154 files, 154 in the database (0 retired), 0 overrides.'
ADM_SHAMAN=$(t_sql "SELECT id FROM monsters WHERE key = 'goblin_shaman'")
expect_body "<td>goblin_shaman</td><td>5</td><td>40</td><td>8</td><td>4</td><td>17</td><td>0</td>"
t_get /admin/monsters/1;   expect_body 'Edit Monster: Blue Slime'; expect_body 'app/content/monsters/blue_slime.lua'
expect_body 'Arcane resistance:'; expect_body 'name="resist.arcane" size="6" value="0"'; expect_body 'Sleep ward:'
expect_body 'name="maxmp" size="6" value="5"'; expect_body 'name="attack_weight" size="6" value="1"'
expect_body 'Loadout:</td><td>none: it only attacks'
t_form_submit /admin/monsters/1 maxhp= maxexp=lots attack_weight=-1
expect_body 'Max Hit Points must be an integer from 1 to 1000000.'; expect_body 'Max Experience must be an integer from 0 to 1000000.'
expect_body 'Attack weight must be an integer from 0 to 1000000.'
admin_eq "SELECT count(*) FROM content_overrides" "0" "invalid monster form not saved"
t_get /admin/monsters/1
t_form_submit /admin/monsters/1 "lore=$(t_sql "SELECT lore FROM monsters WHERE id = 1")" name=Slimer maxhp=2 maxdam=9 resist.arcane=100 ward.sleep=100 resist.frost=-50 maxmp=12 uses_mp=0 attack_weight=3 roams=0
expect_redirect '/admin/monsters/1\?saved=1'
admin_eq "SELECT name || '|' || maxhp || '|' || maxdam || '|' || resist || '|' || ward || '|' || maxmp || '|' || uses_mp || '|' || attack_weight || '|' || roams FROM monsters WHERE id = 1" \
	"Slimer|2|9|arcane=100,frost=-50|sleep=100|12|0|3|0" "monster overrides applied"
admin_eq "SELECT group_concat(field || '=' || value, ';') FROM (SELECT * FROM content_overrides WHERE kind = 'monsters' ORDER BY field)" \
	"attack_weight=3;maxdam=9;maxhp=2;maxmp=12;name=Slimer;resist.arcane=100;resist.frost=-50;roams=0;uses_mp=0;ward.sleep=100" "only the changed fields are overridden"
t_get '/admin/monsters/1?saved=1'; expect_body 'Monster updated.'; expect_body 'File value: Blue Slime'
expect_body '<option value="0" selected>No</option>'
t_get /help/monsters;      expect_body 'Slimer <span class="light">(not met at random)</span>'
expect_body '<td style="width: 12%">Weak to Frost (+50%)<br>Immune to Arcane<br>Wards off Sleep (100%)</td>'
t_get /admin/monsters/1
t_post /admin/monsters/1/reset "csrf=$(t_csrf)&field=*"
expect_redirect '/admin/monsters/1\?saved=1'
admin_eq "SELECT name || '|' || maxhp || '|' || maxmp || '|' || roams FROM monsters WHERE id = 1" "Blue Slime|4|5|1" "monster reset to file"
admin_eq "SELECT count(*) FROM content_overrides" "0" "no monster overrides left"
# the loadout: read-only, from the file
t_get "/admin/monsters/$ADM_SHAMAN"; expect_body 'Edit Monster: Goblin Shaman'
expect_body 'Equipment:</td><td>weapon: Dagger (dagger)'; expect_body 'Spell:</td><td>Hurt (hurt): weight 2'
expect_body 'Spell:</td><td>Heal (heal): weight 3, when its condition holds'
expect_body 'Item:</td><td>Potion (potion): weight 4, stock 2 per encounter, when its condition holds'
expect_body 'edit <code>app/content/monsters/goblin_shaman.lua</code>'
expect_no_body 'name="spells'; expect_no_body 'name="items'; expect_no_body 'name="equipment'
t_get /admin/monsters/999; expect_status 404

t_section "admin: spells"
# spell files app/content/spells/*.lua; admins override name, description, MP, power,
# numbers and message strings (tests/e2e/content.sh covers the files themselves)
t_get /admin/spells;       expect_status 200; expect_body '<a href="/admin/spells/1">Heal</a>'
expect_body '<td>heal</td><td>5</td><td>10</td><td>both</td><td>self</td>'
expect_body '<td>hurt</td><td>5</td><td>15</td><td>fight</td><td>enemy</td>'
expect_body "spells: $(ls app/content/spells | wc -l) files, $(t_sql 'SELECT count(*) FROM spells') in the database (0 retired), 0 overrides."
t_get /admin/spells/6;     expect_status 200; expect_body 'Edit Spell: Hurt'; expect_body 'app/content/spells/hurt.lua'
expect_body 'name="power" size="6" value="15"'; expect_body 'name="mp" size="6" value="5"'
expect_body 'Message hit:'; expect_body 'name="messages.hit" size="70" value="You have cast the %s spell for %d damage."'
expect_body 'Message hit (a monster acting):'; expect_body 'Target:</td><td>enemy</td>'
expect_body 'what the spell does is its code'
expect_body 'Mage (level 4), Warrior (level 5), Paladin (level 5)'
expect_no_body 'name="usable_in"'; expect_no_body 'name="target"'; expect_no_body 'name="cast"'
t_get /admin/spells/99;    expect_status 404
t_post /admin/spells/6 "name=NoToken"; expect_status 403
ADM_HURT_DESC=$(t_sql "SELECT description FROM spells WHERE id = 6")
ADM_HURT_LORE=$(t_sql "SELECT lore FROM spells WHERE id = 6")
t_get /admin/spells/6
t_form_submit /admin/spells/6 "description=$ADM_HURT_DESC" "lore=$ADM_HURT_LORE" mp=-1 power=x name= "messages.immune=100% %s"
expect_status 200; expect_body 'Name must be a one-line string of at most 50 characters, not empty.'
expect_body 'MP must be an integer from 0 to 1000000.'; expect_body 'Power must be an integer from 0 to 1000000.'
expect_body 'Message immune must be a one-line message of at most 500 characters'
admin_eq "SELECT count(*) FROM content_overrides" "0" "invalid spell form not saved"
t_get /admin/spells/6
t_form_submit /admin/spells/6 "description=$ADM_HURT_DESC" "lore=$ADM_HURT_LORE" name=Smite mp=4 power=20 "messages.hit=Smite! %s hits for %d." \
	usable_in=both target=self cast=x
expect_redirect '/admin/spells/6\?saved=1'
admin_eq "SELECT name || '|' || mp || '|' || power || '|' || usable_in || '|' || target || '|' || (instr(messages, char(10) || 'hit=Smite! %s hits for %d.') > 0) FROM spells WHERE id = 6" \
	"Smite|4|20|fight|enemy|1" "spell overrides applied"
admin_eq "SELECT group_concat(field || '=' || value, ';') FROM (SELECT * FROM content_overrides WHERE kind = 'spells' ORDER BY field)" \
	"messages.hit=Smite! %s hits for %d.;mp=4;name=Smite;power=20" "only the changed fields are overridden"
t_get '/admin/spells/6?saved=1'; expect_body 'Spell updated.'; expect_body 'File value: Hurt'; expect_body 'File value: 15'
t_get /help/spells;        expect_body '<td style="width: 50%"><img class="help-icon" src="/static/images/skills/hurt.png" width="24" height="24" alt="">Smite<br>'; expect_body '<td style="width: 25%">20</td>'
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
admin_eq "SELECT power FROM spells WHERE id = 6" "20" "spell overrides survive a sync"
t_get /admin/spells/6
t_post /admin/spells/6/reset "csrf=$(t_csrf)&field=name"
expect_redirect '/admin/spells/6\?saved=1'
admin_eq "SELECT name || '|' || mp FROM spells WHERE id = 6" "Hurt|4" "name reset to file"
t_get /admin/spells/6
t_post /admin/spells/6/reset "csrf=$(t_csrf)&field=*"
admin_eq "SELECT name || '|' || mp || '|' || power || '|' || instr(messages, 'Smite') FROM spells WHERE id = 6" "Hurt|5|15|0" "all reset to file"
admin_eq "SELECT count(*) FROM content_overrides" "0" "no spell overrides left"

t_section "admin: spell icons"
# the list and the form show the icon (default.png without one, e.g. an icon cleared by an
# override); an override must name a PNG that exists in public/images/skills/
t_get /admin/spells
expect_body '<td class="admin-icon-cell"><img src="/static/images/skills/heal.png" width="20" height="20" alt=""></td><td><a href="/admin/spells/1">Heal</a>'
expect_body '<td class="admin-icon-cell"><img src="/static/images/skills/hurt.png" width="20" height="20" alt=""></td><td><a href="/admin/spells/6">Hurt</a>'
t_get /admin/spells/1
expect_body '<span class="admin-icon"><img src="/static/images/skills/heal.png" width="44" height="44" alt="Current icon"> <input type="text" name="icon" size="20" value="heal"></span>'
t_get /admin/spells/6
expect_body '<span class="admin-icon"><img src="/static/images/skills/hurt.png" width="44" height="44" alt="Current icon"> <input type="text" name="icon" size="20" value="hurt"></span>'
expect_body 'A PNG in public/images/skills/, without &quot;.png&quot;'
t_form_submit /admin/spells/6 "description=$ADM_HURT_DESC" "lore=$ADM_HURT_LORE" icon=nope
expect_status 200; expect_body 'Icon names a missing file: '; expect_body '/images/skills/nope.png.'
t_form_submit /admin/spells/6 "description=$ADM_HURT_DESC" "lore=$ADM_HURT_LORE" icon=../heal
expect_status 200; expect_body 'Icon must be the name of a PNG file in public/images/skills/'
admin_eq "SELECT count(*) FROM content_overrides" "0" "invalid icons not saved"
t_get /admin/spells/6
t_form_submit /admin/spells/6 "description=$ADM_HURT_DESC" "lore=$ADM_HURT_LORE" icon=heal
expect_redirect '/admin/spells/6\?saved=1'
admin_eq "SELECT icon FROM spells WHERE id = 6" "heal" "icon override applied"
admin_eq "SELECT group_concat(field || '=' || value, ';') FROM content_overrides WHERE kind = 'spells'" "icon=heal" "only the icon is overridden"
t_get '/admin/spells/6?saved=1'
expect_body '<img src="/static/images/skills/heal.png" width="44" height="44" alt="Current icon"> <input type="text" name="icon" size="20" value="heal">'
expect_body 'Overridden.</span> <span class="small">File value: hurt</span>'
t_post /admin/spells/6/reset "csrf=$(t_csrf)&field=icon"
admin_eq "SELECT icon || '|' || (SELECT count(*) FROM content_overrides) FROM spells WHERE id = 6" "hurt|0" "icon reset to file"
# an override that clears the icon falls back to default.png
t_get /admin/spells/6
t_form_submit /admin/spells/6 "description=$ADM_HURT_DESC" "lore=$ADM_HURT_LORE" icon=
expect_redirect '/admin/spells/6\?saved=1'
admin_eq "SELECT icon FROM spells WHERE id = 6" "" "icon cleared by an override"
t_get /admin/spells
expect_body '<td class="admin-icon-cell"><img src="/static/images/skills/default.png" width="20" height="20" alt=""></td><td><a href="/admin/spells/6">Hurt</a>'
t_get /admin/spells/6
expect_body '<span class="admin-icon"><img src="/static/images/skills/default.png" width="44" height="44" alt="Current icon"> <input type="text" name="icon" size="20" value=""></span>'
t_post /admin/spells/6/reset "csrf=$(t_csrf)&field=icon"
admin_eq "SELECT icon || '|' || (SELECT count(*) FROM content_overrides) FROM spells WHERE id = 6" "hurt|0" "cleared icon reset to file"

t_section "admin: items"
# item files app/content/items/*.lua; admins override name, description, price, attack and
# defense, drop settings, modifiers and a consumable's power and messages (the files:
# tests/lua/test_items.lua)
t_get /admin/items;        expect_status 200; expect_body '<a href="/admin/items/1">Stick</a>'
expect_body '<td>stick</td><td>weapon</td><td>10</td><td>Attack Power +2</td>'
expect_body '<td>demons_sin</td><td>accessory</td><td>0</td><td>Max HP -50, Strength +50</td><td></td>'
expect_body '<td>herb</td><td>consumable</td><td>15</td><td></td><td>Power 30</td>'
ADM_IT=$(ls "$ROOT/app/content/items" | wc -l)
expect_body "items: $ADM_IT files, $ADM_IT in the database (0 retired), 0 overrides."
expect_body '<td class="admin-icon-cell"><img src="/static/images/items/herb.png" width="20" height="20" alt=""></td><td><a href="/admin/items/66">Herb</a>'
expect_body '<td class="admin-icon-cell"><img src="/static/images/items/stick.png" width="20" height="20" alt=""></td><td><a href="/admin/items/1">Stick</a>'
expect_body '<td class="admin-icon-cell"><img src="/static/images/items/dagger.png" width="20" height="20" alt=""></td><td><a href="/admin/items/4">Dagger</a>'
expect_body '<td>wand</td><td>weapon</td><td>75</td><td>Attack Power +2, Casts Magic Bolt, 5 Charges</td>'
t_get /admin/items/71;     expect_status 200; expect_body 'Edit Item: Wand'
expect_body 'name="charges" size="6" value="5"'
expect_body '<img src="/static/images/items/wand.png" width="44" height="44" alt="Current icon"> <input type="text" name="icon" size="20" value="wand">'
t_get /admin/drops;        expect_redirect /admin/items
t_get /admin/items/46;     expect_status 200; expect_body 'Edit Item: Demon&#39;s Sin'; expect_body 'app/content/items/demons_sin.lua'
expect_body 'name="modifiers.1.amount" size="6" value="-50"'; expect_body '<option value="maxhp" selected>maxhp</option>'
expect_body 'name="drop_level" size="6" value="35"'; expect_body '<code>stat stat=maxhp amount=-50; stat stat=strength amount=50</code>'
expect_no_body 'name="category"'; expect_no_body 'name="max_stack"'; expect_no_body 'name="modifiers.1.kind"'
t_get /admin/items/66;     expect_body 'name="power" size="6" value="30"'; expect_body 'name="messages.used" size="70"'
expect_body 'Usable in:</td><td>both</td>'; expect_body 'What the item does is its code'
expect_body 'Sold in:</td><td>Midworld, Newtown, Bris'; expect_no_body 'name="attack"'
t_get /admin/items/9999;   expect_status 404
t_post /admin/items/46 "name=NoToken"; expect_status 403
ADM_DEMON_LORE=$(t_sql "SELECT lore FROM items WHERE id = 46")
t_get /admin/items/46
t_form_submit /admin/items/46 "lore=$ADM_DEMON_LORE" name= price=-1 modifiers.1.amount=x
expect_status 200; expect_body 'Name must be a one-line string of at most 50 characters, not empty.'
expect_body 'Price must be an integer from 0 to 10000000.'; expect_body 'Modifier 1 amount must be an integer from -1000000 to 1000000.'
admin_eq "SELECT count(*) FROM content_overrides" "0" "invalid item form not saved"
t_get /admin/items/46
t_form_submit /admin/items/46 "lore=$ADM_DEMON_LORE" "name=<script>alert(1)</script>" price=123 drop_level=3 modifiers.1.stat=maxmp \
	modifiers.1.amount=-20 category=weapon id=7
expect_redirect '/admin/items/46\?saved=1'
admin_eq "SELECT id || '|' || name || '|' || category || '|' || price || '|' || drop_level || '|' || modifiers FROM items WHERE key = 'demons_sin'" \
	"46|<script>alert(1)</script>|accessory|123|3|stat stat=maxmp amount=-20; stat stat=strength amount=50" "item overrides applied"
admin_eq "SELECT group_concat(field || '=' || value, ';') FROM (SELECT * FROM content_overrides WHERE kind = 'items' ORDER BY field)" \
	"drop_level=3;modifiers.1.amount=-20;modifiers.1.stat=maxmp;name=<script>alert(1)</script>;price=123" "only the changed fields are overridden"
t_get '/admin/items/46?saved=1'; expect_body 'Item updated.'; expect_body 'File value: maxhp'; expect_body 'File value: -50'
t_get /admin/items;        expect_body '&lt;script&gt;alert(1)&lt;/script&gt;'; expect_no_body '<script>alert'
t_get /help/items
expect_row '>&lt;script&gt;alert(1)&lt;/script&gt;</td><td style="width: 15%">3</td><td style="width: 30%">Max MP -20</td>'
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
admin_eq "SELECT price || '|' || modifiers FROM items WHERE id = 46" "123|stat stat=maxmp amount=-20; stat stat=strength amount=50" "item overrides survive a sync"
t_get /admin/items/66
t_form_submit /admin/items/66 "description=$(t_sql "SELECT description FROM items WHERE id = 66")" \
	"lore=$(t_sql "SELECT lore FROM items WHERE id = 66")" power=45 sellable=0
admin_eq "SELECT power || '|' || sellable || '|' || (SELECT count(*) FROM content_overrides WHERE key = 'herb') FROM items WHERE id = 66" \
	"45|0|2" "power override"
t_get /admin/items/66
t_post /admin/items/66/reset "csrf=$(t_csrf)&field=*"
t_get /admin/items/46
t_post /admin/items/46/reset "csrf=$(t_csrf)&field=name"
expect_redirect '/admin/items/46\?saved=1'
admin_eq "SELECT name || '|' || price FROM items WHERE id = 46" "Demon's Sin|123" "name reset to file"
t_get /admin/items/46
t_post /admin/items/46/reset "csrf=$(t_csrf)&field=*"
admin_eq "SELECT name || '|' || price || '|' || drop_level || '|' || modifiers FROM items WHERE id = 46" \
	"Demon's Sin|0|35|stat stat=maxhp amount=-50; stat stat=strength amount=50" "all reset to file"
admin_eq "SELECT power || '|' || sellable FROM items WHERE id = 66" "30|1" "herb reset"
admin_eq "SELECT count(*) FROM content_overrides" "0" "no item overrides left"

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
expect_body 'Experience base 18, stages global (2x2,1.5x8,1.25x5,1.125x28)'
expect_body "<tr><td>2</td><td>18</td><td>2</td><td>0</td><td>4</td><td>1</td><td>2</td><td>1</td><td>$(t_sql "SELECT name FROM spells WHERE id = 1")</td></tr>"
expect_body '<tr><td>10</td><td>2,368</td><td>0</td><td>10</td>'
expect_no_body 'name="exp_base"'; expect_no_body 'name="levels'
t_get /admin/classes/99;   expect_status 404
t_post /admin/classes/2 "name=NoToken"; expect_status 403
adm_class_post() {  # adm_class_post ID 'field=value&...' (other fields: the current values)
	local id=$1 over=$2 data f v
	t_get "/admin/classes/$id"
	data="csrf=$(t_csrf)"
	for f in name description lore sort playable start_hp start_mp start_tp start_strength start_dexterity; do
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
admin_eq "SELECT charclass || '|' || currenthp || '|' || base_maxhp || '|' || base_maxmp || '|' || base_maxtp || '|' || strength || '|' || (strength + base_attack) FROM users WHERE username = 'admwarrior'" \
	"2|20|20|0|10|5|5" "new character gets the overridden starting stats"
t_login admwarrior pw1
t_get /character;          expect_body 'Class: Fighter &lt;b&gt;'
t_jar admadmin
# overrides survive a sync
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content sync: $(cat "$T/content.log")"
grep -qF "Content synced (statuses: $(ls app/content/statuses | wc -l), 0 new, 0 retired; summons: $(ls app/content/summons | wc -l), 0 new, 0 retired; spells: $(ls app/content/spells | wc -l), 0 new, 0 retired; classes: 3, 0 new, 0 retired; items: $(ls app/content/items | wc -l), 0 new, 0 retired; monsters: $(ls app/content/monsters | wc -l), 0 new, 0 retired)." "$T/content.log" && t_ok || t_fail "sync output: $(cat "$T/content.log")"
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
t_get /admin/users/$ADM_UID; expect_body 'Username:'; expect_body 'Fight:'; expect_no_body 'pbkdf2$'
expect_no_body 'Current Monster'
# the fight and world statuses, read-only (the fight tables)
t_fight admtester 5 9; t_fight_status admtester 2 sleep 'chance=i:4'; t_fight_status admtester 1 uber_damage 'pct=i:10' 3
t_sql "INSERT INTO user_statuses (user_id, status_id, position, ticks_left) SELECT $ADM_UID, id, 1, 7 FROM statuses WHERE key = 'regen'"
t_get /admin/users/$ADM_UID; expect_body 'round 2; you (Damage Up (3)); Shadow 9/10 HP (Asleep)'; expect_body 'Regenerating (7)'
t_fight_clear admtester; t_sql "DELETE FROM user_statuses; UPDATE users SET currentaction = 'In Town' WHERE id = $ADM_UID"
t_get /admin/users/$ADM_UID
expect_body 'name="charclass"'; expect_no_body 'name="difficulty"'
expect_body '<option value="2">Warrior</option>'; expect_body '<option value="1" selected>Mage</option>'
t_form_submit /admin/users/$ADM_UID email= gold=lots
expect_body 'Email is required.'; expect_body 'Gold must be a number.'
t_get /admin/users/$ADM_UID
t_form_submit /admin/users/$ADM_UID "charname=<i>Hero</i>" gold=5000 level=7 authlevel=2 currentaction=Exploring \
	"spells=revive, heal" username=evil password=plain regdate=1 id=4242 onlinetime=3
expect_redirect "/admin/users/$ADM_UID\\?saved=1"
admin_eq "SELECT username || '|' || charname || '|' || gold || '|' || level || '|' || authlevel || '|' || currentaction || '|' || $T_KNOWN || '|' || (regdate > 1) FROM users WHERE id = $ADM_UID" \
	"admtester|<i>Hero</i>|5000|7|2|Exploring|1,2|1" "user saved"
admin_eq "SELECT count(*) FROM user_spells WHERE user_id = $ADM_UID AND learned_level IS NULL" "2" "admin-given spells: level unknown"
t_get /admin/users/$ADM_UID; expect_body 'name="spells" size="50" maxlength="1000" value="heal, revive"'
t_form_submit /admin/users/$ADM_UID "spells=heal, fireball"
expect_body "Spells: there is no spell &#39;fireball&#39;."
admin_eq "SELECT $T_KNOWN FROM users WHERE id = $ADM_UID" "1,2" "invalid spells not saved"
t_get /admin/users/$ADM_UID
t_form_submit /admin/users/$ADM_UID "spells=revive"
admin_eq "SELECT $T_KNOWN FROM users WHERE id = $ADM_UID" "2" "spells forgotten"
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
			 DELETE FROM towns WHERE id = 2; INSERT INTO towns SELECT * FROM adm_snap_towns; DROP TABLE adm_snap_towns;
			 DELETE FROM town_items WHERE town_id = 2; INSERT INTO town_items SELECT * FROM adm_snap_town_items;
			 DROP TABLE adm_snap_town_items;
			 DELETE FROM town_maps WHERE town_id = 2; INSERT INTO town_maps SELECT * FROM adm_snap_town_maps;
			 DROP TABLE adm_snap_town_maps;
			 DELETE FROM news WHERE id > $ADM_NEWS_MAX; DELETE FROM forum WHERE id > $ADM_FORUM_MAX;"
fi
