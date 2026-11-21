# tests/e2e/pure.sh :: GETs don't change the game (docs/APP.md "Pure GETs"). Every GET
# route (the list below must cover the router's: GET /__test/routes) is requested by a
# player in town, exploring, fighting (with statuses and an ally), after a victory with a
# drop to take, after a death, and by an administrator; the game's tables are the same
# before and after (all but the session bookkeeping: sessions, meta, users.onlinetime and
# users.online). Sourced by tests/run.sh.
if t_has_sql; then

# pattern -> the path requested for it (ids that exist on a fresh install, or $PU_*)
pu_path() {
	case $1 in
		/shop/buy/#id) echo /shop/buy/1 ;;
		/maps/buy/#id) echo /maps/buy/2 ;;
		/inventory/discard/#id) echo "/inventory/discard/$PU_ENTRY" ;;
		/character/#id) echo /character/1 ;;
		/forum/#board) echo /forum/1 ;;
		/forum/#board/new) echo /forum/1/new ;;
		/forum/thread/#id) echo "/forum/thread/$PU_THREAD" ;;
		/news/#id) echo /news/1 ;;
		/admin/*/#id) echo "${1%/#id}/1" ;;
		/live) echo /live ;;
		*) echo "$1" ;;
	esac
}
PU_ROUTES="/ /admin /admin/broadcast /admin/classes /admin/classes/#id /admin/drops /admin/items /admin/items/#id
	/admin/levels /admin/monsters /admin/monsters/#id /admin/news /admin/server /admin/settings /admin/spells
	/admin/spells/#id /admin/statuses /admin/statuses/#id /admin/summons /admin/summons/#id /admin/towns
	/admin/towns/#id /admin/users /admin/users/#id /babble /changelog /changepassword /character /character/#id
	/dead /drop /fight /forum /forum/#board /forum/#board/new /forum/new /forum/thread/#id /help /help/items /hotbar
	/help/levels /help/monsters /help/spells /inn /inventory /inventory/discard/#id /live /live/state /login
	/lostpassword /map /maps /maps/buy/#id /news /news/#id /ninja /online /register /shop /shop/buy/#id
	/travel /verify /victory /__test/routes"

t_section "pure GETs: the list covers every GET route"
t_jar default
t_get /__test/routes; expect_status 200
missing=
for pattern in $(sed -n 's/^GET //p' "$BODY"); do
	case $pattern in /__test/*) continue ;; esac   # run.sh's own test routes
	case " $(echo $PU_ROUTES) " in *" $pattern "*) ;; *) missing="$missing $pattern" ;; esac
done
[ -z "$missing" ] && t_ok || t_fail "GET routes not requested by pure.sh:$missing"

# The game's tables, one line per row (sorted), but the session bookkeeping.
pu_snap() {
	local t cols
	for t in $(t_sql "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT IN ('sessions', 'meta', 'sqlite_sequence') ORDER BY name"); do
		cols=$(t_sql "SELECT group_concat('quote(\"' || name || '\")', ' || ''|'' || ') FROM pragma_table_info('$t')
			WHERE NOT ('$t' = 'users' AND name IN ('onlinetime', 'online'))")
		t_sql "SELECT '$t|' || $cols FROM \"$t\"" | sort
	done
}
# Every GET route with the current jar; the tables must not change.
pu_all() {  # pu_all LABEL
	local before pattern path
	t_get /; before=$(pu_snap)
	for pattern in $PU_ROUTES; do
		path=$(pu_path "$pattern")
		if [ "$path" = /live ]; then t_get /live --max-time 1; else t_get "$path"; fi
		t_head "$path"
	done
	local after; after=$(pu_snap)
	if [ "$after" = "$before" ]; then t_ok
	else t_fail "$1: GETs changed the game: $(diff <(echo "$before") <(echo "$after") | head -6 | tr '\n' ' ')"; fi
}

t_jar pure
t_register pureuser purepw1 pure@example.com Pureuser 2
t_login pureuser purepw1
PQ="WHERE username = 'pureuser'"
t_give pureuser herb 2
PU_ENTRY=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id $PQ")
PU_THREAD=$(t_sql "SELECT thread_id FROM news ORDER BY id LIMIT 1")

t_section "pure GETs: in town"
# (the snapshot sees a change in the game)
before=$(pu_snap); t_sql "UPDATE users SET gold = gold + 1 $PQ"
[ "$(pu_snap)" != "$before" ] && t_ok || t_fail "pu_snap missed a change"
t_sql "UPDATE users SET gold = gold - 1 $PQ"
pu_all "in town"

t_section "pure GETs: exploring"
t_sql "UPDATE users SET currentaction = 'Exploring', latitude = 3, longitude = 4 $PQ"
pu_all "exploring"

t_section "pure GETs: fighting"
t_sql "UPDATE users SET currenthp = 5000, base_maxhp = 5000 $PQ"
t_fight_new pureuser
t_fight_status pureuser 1 regen 'amount=i:5' 3
t_sql "INSERT INTO fight_combatants (user_id, id, side, kind, entity_id, hp, maxhp, turns_left)
	SELECT u.id, 9, 'ally', 'summon', s.id, 20, 30, 4 FROM users u, summons s $PQ AND s.key = 'wolf'"
t_get /fight; expect_body 'You are fighting a'; expect_body 'Your <b>Wolf</b>: 20 / 30 HP'
pu_all "fighting"

t_section "pure GETs: after a victory with a drop"
t_fight pureuser 1 0
t_sql "UPDATE users SET level = 100 $PQ"
for _ in $(seq 1 60); do
	t_sql "DELETE FROM fights WHERE user_id = (SELECT id FROM users $PQ); UPDATE users SET dropcode = 0 $PQ"
	t_fight pureuser 1 0
	t_fight_win
	[ "$(t_sql "SELECT dropcode FROM users $PQ")" != 0 ] && break
done
t_get /victory; expect_status 200
pu_all "after a victory"

t_section "pure GETs: after a death"
t_fight pureuser 151 30000
t_sql "UPDATE users SET currenthp = 1, dexterity = 0, base_defense = 0, dropcode = 0 $PQ"
t_get /fight; t_round "csrf=$(t_csrf)&fight=Fight"; expect_body '<b>You have died.</b>'
pu_all "after a death"

t_section "pure GETs: an administrator"
t_jar pureadmin
t_login "$ADMIN_USER" "$ADMIN_PASS"
pu_all "administrator"
t_jar pure
t_fight_clear pureuser
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 $PQ"

fi
