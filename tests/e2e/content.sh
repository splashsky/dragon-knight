# tests/e2e/content.sh :: content files (app/content/{classes,spells}/*.lua) on the running
# server: a new file becomes a playable class on the next request, edits sync, a deleted
# file retires its class (its characters keep playing), a restored file brings it back,
# overrides survive, invalid content fails `dk check` (naming the file) while the game
# keeps the last good content, a full level-up of a new class, and a new spell learned
# through a class file and cast (a class listing an unknown spell fails `dk check`).
# Sourced by tests/run.sh; works on the test server's copy of app/ and cleans up after itself.

CT_DIR="$T/app/content/classes"
CT_SPELLS="$T/app/content/spells"
ct_eq() {  # ct_eq "SQL" expected label
	local got
	got=$(t_sql "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: expected '$2', got '$got'"; fi
}
# Wait (max ~5 s) until GET PATH no longer contains TEXT.
ct_wait_gone() {
	local i
	for i in $(seq 1 50); do
		t_get "$1"
		grep -qF -- "$2" "$BODY" || return 0
		sleep 0.1
	done
	return 1
}
# ct_knight NAME HP [LUA]: write the test class file (flat experience, "1x1": 10 per level;
# every level +2 HP, +1 MP/strength/dexterity; Hurt and Heal at level 3; LUA: more lines)
ct_knight() {
	cat > "$CT_DIR/knight.lua.tmp" <<EOF
local levels = {}
for level = 2, 100 do levels[level] = { hp = 2, mp = 1, strength = 1, dexterity = 1 } end
levels[3].spells = { "hurt", "heal" }
${3:-}
return {
	name = "$1",
	description = "Sturdy.\nTest class.",
	sort = 0,
	start_hp = $2, start_mp = 0, start_tp = 12, start_strength = 7, start_dexterity = 3,
	exp_base = 10, exp_stages = "1x1",
	levels = levels,
}
EOF
	mv "$CT_DIR/knight.lua.tmp" "$CT_DIR/knight.lua"
}

if ! t_has_sql; then
	echo "content.sh: skipped (needs sqlite3 or python3)"
else

t_section "content: a new class file"
t_jar ctnew
ct_knight Knight 30
t_wait_for /register '<option value="4">Knight</option>' && t_ok || t_fail "new class not offered"
# sort 0: listed first
grep -o '<option value="[0-9]*">[A-Za-z]*</option>' "$BODY" | head -n1 | grep -qF '>Knight<' && t_ok || t_fail "sort order"
ct_eq "SELECT id || '|' || key || '|' || name || '|' || start_hp || '|' || exp_base || '|' || retired FROM classes WHERE key = 'knight'" \
	"4|knight|Knight|30|10|0" "class row"
ct_eq "SELECT count(*) || '|' || sum(hp) FROM class_levels WHERE class_id = 4" "99|198" "class levels"
ct_eq "SELECT group_concat(spell_id) FROM class_spells WHERE class_id = 4 AND level = 3" "1,6" "class spells"
grep -qF 'content synced (spells: 19, 0 new, 0 retired, 0 restored; classes: 4, 1 new, 0 retired, 0 restored)' "$T/server.log" && t_ok || t_fail "sync not logged"
t_get /help;          expect_body '<b>Knight</b>'; expect_body '<li>Test class.</li>'; expect_body 'There are four character classes'
t_get /help/levels;   expect_body 'Knight Levels'
"$BIN" content status --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk content status"
grep -qF 'classes: 4 files, 4 in the database (0 retired), 0 overrides' "$T/content.log" && t_ok || t_fail "status: $(cat "$T/content.log")"

t_section "content: registration and a full level-up"
t_jar ctknight
t_register ctknight ctpw1 ctknight@example.com CtKnight 4
expect_body 'Your account was created succesfully'
ct_eq "SELECT charclass || '|' || currenthp || '|' || maxhp || '|' || maxmp || '|' || currenttp || '|' || maxtp || '|' || strength || '|' || dexterity || '|' || attackpower || '|' || defensepower FROM users WHERE username = 'ctknight'" \
	"4|30|30|0|12|12|7|3|7|3" "starting stats from the class"
t_login ctknight ctpw1
t_get /character;     expect_body 'Class: Knight'; expect_body 'Next Level: 10'
# a Blue Slime gives 1 experience: 89 + 1 = 90 = level 10 (10 per level)
t_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 3, currentmonster = 1, currentmonsterhp = 0,
	experience = 89 WHERE username = 'ctknight'"
t_get /victory;       expect_status 200; expect_body 'You have gained 9 levels!'; expect_body 'You have learned 2 new spells.'
# HP: 9 x 2 + 10 (milestone at 10); TP: 1 + 8 x 2; MP, strength, dexterity: 9 x 1
ct_eq "SELECT level || '|' || experience || '|' || maxhp || '|' || maxmp || '|' || maxtp || '|' || strength || '|' || dexterity || '|' || attackpower || '|' || defensepower FROM users WHERE username = 'ctknight'" \
	"10|90|58|9|29|16|12|16|12" "level-up of the new class"
ct_eq "SELECT group_concat(s.key || '@' || us.learned_level) FROM (SELECT * FROM user_spells ORDER BY spell_id) us
	JOIN spells s ON s.id = us.spell_id JOIN users u ON u.id = us.user_id WHERE u.username = 'ctknight'" \
	"heal@3,hurt@3" "spells learned at level 3"
t_get /character;     expect_body 'Next Level: 100'
expect_body "$(t_sql "SELECT name FROM spells WHERE id = 6")"

t_section "content: edits sync"
ct_knight Paladin2 40
t_wait_for /register '>Paladin2</option>' && t_ok || t_fail "edited name not synced"
ct_eq "SELECT name || '|' || start_hp FROM classes WHERE id = 4" "Paladin2|40" "edit synced"
ct_eq "SELECT maxhp FROM users WHERE username = 'ctknight'" "58" "existing characters keep their stats"

t_section "content: overrides survive edits"
t_jar admin
t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/classes/4; expect_body 'Edit Class: Paladin2'; expect_body 'knight.lua'
t_form_submit /admin/classes/4 name=Lancer "description=$(printf 'Sturdy.\nTest class.')"
expect_redirect '/admin/classes/4\?saved=1'
ct_eq "SELECT name FROM classes WHERE id = 4" "Lancer" "override applied"
ct_knight Knight 30
t_jar ctnew
for _ in $(seq 1 50); do
	[ "$(t_sql "SELECT start_hp FROM classes WHERE id = 4")" = 30 ] && break
	t_get /login; sleep 0.1
done
ct_eq "SELECT name || '|' || start_hp FROM classes WHERE id = 4" "Lancer|30" "override kept, file edit synced"
t_jar admin
t_get /admin/classes/4; expect_body 'File value: Knight'
t_post /admin/classes/4/reset "csrf=$(t_csrf)&field=name"
expect_redirect '/admin/classes/4\?saved=1'
ct_eq "SELECT name FROM classes WHERE id = 4" "Knight" "reset to file"

t_section "content: a deleted file retires the class"
rm "$CT_DIR/knight.lua"
t_jar ctnew
ct_wait_gone /register '>Knight</option>' && t_ok || t_fail "retired class still offered"
ct_eq "SELECT retired || '|' || name FROM classes WHERE id = 4" "1|Knight" "retired, row kept"
ct_eq "SELECT count(*) FROM class_levels WHERE class_id = 4" "99" "levels kept"
t_register ctlate ctpw1 ctlate@example.com CtLate 4
expect_body 'Character Class is invalid.'
t_jar ctknight
t_get /;              expect_status 200
t_get /character;     expect_body 'Class: Knight'
t_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 3, currentmonster = 1, currentmonsterhp = 0,
	experience = 99 WHERE username = 'ctknight'"
t_get /victory;       expect_status 200; expect_body 'You have gained a level!'
ct_eq "SELECT level || '|' || maxhp FROM users WHERE username = 'ctknight'" "11|60" "a retired class keeps leveling"
t_get /help;          expect_no_body '<b>Knight</b>'
t_jar admin
t_get /admin/classes; expect_body 'Knight</a> <span class="highlight">(retired)</span>'
expect_body 'classes: 3 files, 4 in the database (1 retired), 0 overrides.'
t_get /admin/classes/4; expect_body 'Retired:'
t_get /admin/users/$(t_sql "SELECT id FROM users WHERE username = 'ctknight'")
expect_body '<option value="4" selected>Knight (retired)</option>'

t_section "content: a restored file un-retires it"
ct_knight Knight 30
t_jar ctnew
t_wait_for /register '<option value="4">Knight</option>' && t_ok || t_fail "restored class not offered"
ct_eq "SELECT retired || '|' || id FROM classes WHERE key = 'knight'" "0|4" "same id, not retired"

t_section "content: invalid content"
printf 'return { name = 5, levels = {} }\n' > "$CT_DIR/broken.lua"
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk check passed with invalid content" || t_ok
grep -qF 'broken.lua' "$T/content.log" && t_ok || t_fail "dk check does not name the file: $(cat "$T/content.log")"
grep -qF "field 'name' must be a one-line string" "$T/content.log" && t_ok || t_fail "dk check message: $(cat "$T/content.log")"
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk content sync passed with invalid content" || t_ok
grep -qF 'broken.lua' "$T/content.log" && t_ok || t_fail "sync error: $(cat "$T/content.log")"
t_jar admin
t_wait_for /admin 'Content files have errors' && t_ok || t_fail "admin pages do not show the content error"
expect_body 'broken.lua'
t_jar ctknight
t_get /;              expect_status 200
t_get /character;     expect_body 'Class: Knight'
t_jar ctnew
t_get /register;      expect_status 200; expect_body '>Knight</option>'
ct_eq "SELECT count(*) FROM classes" "4" "last good content kept"
grep -qF 'content not synced, the game keeps the previous content' "$T/server.log" && t_ok || t_fail "content error not logged"
# a syntax error is reported with its file and line too
printf 'return {\n' > "$CT_DIR/broken.lua"
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk check passed with a syntax error" || t_ok
grep -qF 'broken.lua:2:' "$T/content.log" && t_ok || t_fail "syntax error: $(cat "$T/content.log")"
# a bad file name
rm "$CT_DIR/broken.lua"
printf 'return {}\n' > "$CT_DIR/Bad-Name.lua"
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk check passed with a bad file name" || t_ok
grep -qF "Bad-Name.lua: the file name is the class's key" "$T/content.log" && t_ok || t_fail "bad name: $(cat "$T/content.log")"
rm "$CT_DIR/Bad-Name.lua"
t_jar admin
ct_wait_gone /admin 'Content files have errors' && t_ok || t_fail "content error not cleared"
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_ok || t_fail "dk check after the fix: $(cat "$T/content.log")"
grep -qF 'content: ok (19 spells, 4 classes)' "$T/content.log" && t_ok || t_fail "check output: $(cat "$T/content.log")"

t_section "content: a new spell, learned through a class file"
cat > "$CT_SPELLS/zap.lua" <<'EOF'
return {
	name = "Zap",
	description = "A test spell.",
	mp = 3,
	effects = { { kind = "damage", max = 6, min = 6 }, { kind = "buff_defense_pct", pct = 20 } },
}
EOF
t_jar ctnew
t_wait_for /help/spells '>Zap<br>' && t_ok || t_fail "new spell not on the help page"
expect_body '<td style="width: 25%">Hurt + +Defense (%)</td><td style="width: 25%">6-6, 20</td>'
ct_eq "SELECT id || '|' || key || '|' || usable_in || '|' || effects || '|' || retired FROM spells WHERE key = 'zap'" \
	"20|zap|fight|damage max=6 min=6; buff_defense_pct pct=20|0" "spell row"
# ctknight is level 11 (100 experience, 10 per level): Zap at level 12
ct_knight Knight 30 'levels[12].spells = { "zap" }'
for _ in $(seq 1 50); do
	[ "$(t_sql "SELECT count(*) FROM class_spells WHERE class_id = 4 AND level = 12")" = 1 ] && break
	t_get /login; sleep 0.1
done
ct_eq "SELECT spell_id FROM class_spells WHERE class_id = 4 AND level = 12" "20" "class learns the new spell"
t_jar ctknight
t_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 3, currentmonster = 1, currentmonsterhp = 0,
	experience = 109 WHERE username = 'ctknight'"
t_get /victory;       expect_body 'You have gained a level!'; expect_body 'You have learned a new spell.'
ct_eq "SELECT us.learned_level FROM user_spells us JOIN users u ON u.id = us.user_id WHERE u.username = 'ctknight' AND us.spell_id = 20" \
	"12" "learned at level 12"
t_get /;              expect_no_body 'action="/spell/20"'   # fight-only: not a Fast Spell
t_post /spell/20 "csrf=$(t_csrf)"; expect_body 'This is not a healing spell.'
# cast in a fight: both effects, MP spent (Red Slime: no immunity)
t_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 2, currentmonsterhp = 50,
	currentmonstersleep = 0, currentmonsterimmune = 0, currentuberdefense = 0, currentmp = 10, currenthp = 500,
	maxhp = 500 WHERE username = 'ctknight'"
t_get /fight;         expect_body '<option value="20">Zap</option>'
t_post /fight "csrf=$(t_csrf)&spell=Spell&userspell=20"
expect_body 'You have cast the Zap spell for 6 damage.<br>You have cast the Zap spell, and will gain 20% defense until the end of this fight.'
ct_eq "SELECT currentmonsterhp || '|' || currentuberdefense || '|' || currentmp FROM users WHERE username = 'ctknight'" \
	"44|20|7" "spell effects saved"

t_section "content: a class listing an unknown or deleted spell fails dk check"
ct_knight Knight 30 'levels[12].spells = { "zap", "nope" }'
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk check passed with an unknown spell" || t_ok
grep -qF "knight.lua: levels.12.spells: no spell 'nope' (" "$T/content.log" && t_ok || t_fail "unknown spell: $(cat "$T/content.log")"
grep -qF "spells/nope.lua)" "$T/content.log" && t_ok || t_fail "unknown spell path: $(cat "$T/content.log")"
ct_knight Knight 30 'levels[12].spells = { "zap" }'
mv "$CT_SPELLS/zap.lua" "$T/zap.lua"
"$BIN" check --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk check passed with a deleted spell" || t_ok
grep -qF "knight.lua: levels.12.spells: no spell 'zap'" "$T/content.log" && t_ok || t_fail "deleted spell: $(cat "$T/content.log")"
"$BIN" content sync --config "$CONFIG" >"$T/content.log" 2>&1 && t_fail "dk content sync passed" || t_ok
ct_eq "SELECT retired FROM spells WHERE key = 'zap'" "0" "nothing synced"

t_section "content: a deleted spell file retires the spell; characters keep it"
ct_knight Knight 30
t_jar ctknight
for _ in $(seq 1 50); do
	[ "$(t_sql "SELECT retired FROM spells WHERE key = 'zap'")" = 1 ] && break
	t_get /login; sleep 0.1
done
ct_eq "SELECT retired || '|' || name FROM spells WHERE id = 20" "1|Zap" "retired, row kept"
t_get /help/spells;   expect_no_body '>Zap<'
t_get /character;     expect_body 'Zap<br>'
t_sql "UPDATE users SET currentmp = 10, currentmonsterhp = 50 WHERE username = 'ctknight'"
t_get /fight;         expect_body '<option value="20">Zap</option>'
t_post /fight "csrf=$(t_csrf)&spell=Spell&userspell=20"; expect_body 'You have cast the Zap spell for 6 damage.'
t_jar admin
t_get /admin/spells;  expect_body 'Zap</a> <span class="highlight">(retired)</span>'
expect_body 'spells: 19 files, 20 in the database (1 retired), 0 overrides.'
rm -f "$T/zap.lua"

# clean up: the test class and spell are retired (rows stay, like on a real server)
rm -f "$CT_DIR/knight.lua"
t_jar ctnew
ct_wait_gone /register '>Knight</option>' && t_ok || t_fail "cleanup"
t_sql "DELETE FROM user_spells WHERE user_id = (SELECT id FROM users WHERE username = 'ctknight');
	DELETE FROM users WHERE username = 'ctknight'"
fi
