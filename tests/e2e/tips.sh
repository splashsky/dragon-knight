# tests/e2e/tips.sh :: tooltips and lore (docs/APP.md "Tooltips", "Lore"): tooltip.js on
# every layout; the tooltip templates of the fight menu's spell buttons (name, MP, where it
# can be cast, description, lore; disabled buttons too), of the monster fought, of Fast
# Spells, of the registration page's classes and in the JSON fight fragments; lore on the
# help pages; admin lore overrides (escaped everywhere, reset to the file, too long
# refused); and content files with invalid lore failing `dk check`.
# Sourced by tests/run.sh.

tp_eq() {  # tp_eq "SQL" expected label
	local got
	got=$(t_sql "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: expected '$2', got '$got'"; fi
}
# expect_body for text over several lines (grep -F would take each line as a pattern)
tp_has() {
	if tr '\n' ' ' < "$BODY" | grep -qF -- "$(printf '%s' "$1" | tr '\n' ' ')"; then t_ok; else t_fail "body lacks: $1"; fi
}
TP_HEAL_LORE='The first word every young Mage learns, and the last one a wise one forgets. Spoken softly over a wound, it draws warmth back into tired flesh. Old soldiers say a Heal cast in time is worth a hundred herbs.'
TP_SLIME_LORE='The humblest monster of the land, a wobbling drop of blue jelly that hops along the roads near Midworld. Its bite barely stings, yet every hero alive remembers the first one they defeated. Some say slimes are what is left when a spell goes wrong.'

if ! t_has_sql; then
	echo "tips.sh: skipped (needs sqlite3 or python3)"
else

t_section "tips: tooltip.js on every layout"
t_get /static/js/tooltip.js; expect_status 200; expect_body 'function place(t, tip, vw, vh, side)'
t_jar tipsout; t_reset_jar
t_get /login;    expect_body '<script src="/static/js/tooltip.js" defer></script>'
t_get /help;     expect_body '<script src="/static/js/tooltip.js" defer></script>'   # minimal layout
t_get /static/css/dk.css; expect_body '.dk-tip-arrow'; expect_body '.tip-lore'

t_section "tips: the classes on the registration page"
t_get /register
expect_body 'The classes: <span class="tip-term" data-tip data-tip-side="bottom" tabindex="0">Mage<template class="tip"><div class="tip-title">Mage</div><div class="tip-meta">Starts with 15 HP, 0 MP</div><ul class="tip-lines"><li>Fast level-ups</li><li>High hit points</li>'
expect_body '<li>0 +attack spells</li></ul><div class="tip-lore"><p>In the towers of Midworld the old masters still teach the words that bend the world: a whisper that closes wounds, a cry that calls down fire. Mages are frail in a brawl, and every adventurer they have saved will tell you so. Few of them mind.</p></div></template></span>'
expect_body '>Warrior<template class="tip"><div class="tip-title">Warrior</div>'
expect_body '>Paladin<template class="tip"><div class="tip-title">Paladin</div>'
expect_body 'name="charclass"'

t_section "tips: the fight menu's spells and the monster"
t_jar tips; t_register tipper tippw1 tips@example.com Tipper; t_login tipper tippw1
t_sql "UPDATE users SET currenthp = 5, base_maxhp = 30, currentmp = 7, base_maxmp = 30 WHERE username = 'tipper'"
t_spells tipper 1,2,6    # Heal (5 MP), Revive (10 MP: more than the 7 MP left), Hurt (5 MP)
t_fight tipper 1 4
t_get /fight; expect_status 200
# the monster's name: its level and lore (Blue Slime has no description)
expect_body 'You are fighting a <b class="tip-term" data-tip tabindex="0">Blue Slime<template class="tip"><div class="tip-title">Blue Slime</div><div class="tip-meta">Level 1</div><div class="tip-lore"><p>'"$TP_SLIME_LORE"'</p></div></template></b></p>'
# each button in a span that carries its tooltip: name, MP, where, description, lore
expect_body '<span class="spell-tip" data-tip><button class="spell-btn" type="submit" name="spell" value="1" title="Heal (5 MP)" aria-label="Heal (5 MP)"><img src="/static/images/skills/heal.png" width="44" height="44" alt=""><span class="spell-mp" aria-hidden="true">5</span></button><template class="tip"><div class="tip-title">Heal</div><div class="tip-meta">5 MP · In fights and in town</div><div class="tip-body"><p>Restores hit points, in a fight or out of it.</p></div><div class="tip-lore"><p>'"$TP_HEAL_LORE"'</p></div></template></span>'
# no lore: no lore block
expect_body 'value="6" title="Hurt (5 MP)" aria-label="Hurt (5 MP)"><img src="/static/images/skills/default.png" width="44" height="44" alt=""><span class="spell-mp" aria-hidden="true">5</span></button><template class="tip"><div class="tip-title">Hurt</div><div class="tip-meta">5 MP · In fights</div><div class="tip-body"><p>Hurts the monster, whatever its armor. Some monsters are immune.</p></div></template></span>'
expect_no_body '<div class="tip-lore"></div>'; expect_no_body '<div class="tip-body"></div>'
# a disabled button keeps its tooltip: the span is the trigger (pointer events pass to it)
expect_body '<span class="spell-tip spell-tip-short" data-tip><button class="spell-btn" type="submit" name="spell" value="2" title="Revive (10 MP)" aria-label="Revive (10 MP)" disabled><img'
expect_body '<span class="spell-mp" aria-hidden="true">10</span></button><template class="tip"><div class="tip-title">Revive</div><div class="tip-meta">10 MP · In fights and in town</div>'
# Fast Spells in the right column: Heal and Revive, opening to the left
expect_body '<form class="spell-tip" method="post" action="/spell/1" data-tip data-tip-side="left">'
expect_body '<form class="spell-tip spell-tip-short" method="post" action="/spell/2" data-tip data-tip-side="left">'
[ "$(grep -o '<div class="tip-title">Heal</div>' "$BODY" | wc -l)" = 2 ] && t_ok || t_fail "Heal's tooltip in the menu and in Fast Spells"
# the JSON fight API's fragments are the same templates (fight.js swaps them in as they are)
t_get /fight -H 'Accept: application/json'; expect_status 200
if command -v python3 >/dev/null; then
	python3 - "$BODY" "$TP_HEAL_LORE" <<'PY' && t_ok || t_fail "fight fragments without the tooltips"
import json, sys
d = json.load(open(sys.argv[1]))
main, right = d["fragments"]["main"], d["fragments"]["nav_right"]
assert '<span class="spell-tip" data-tip><button class="spell-btn" type="submit" name="spell" value="1"' in main
assert '<div class="tip-lore"><p>' + sys.argv[2] + '</p></div></template></span>' in main
assert '>Blue Slime<template class="tip"><div class="tip-title">Blue Slime</div><div class="tip-meta">Level 1</div>' in main
assert 'data-tip data-tip-side="left"><input type="hidden" name="csrf"' in right and '<div class="tip-title">Heal</div>' in right
PY
fi
t_fight_clear tipper

t_section "tips: the inventory panel's gear"
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 WHERE username = 'tipper'"
t_give tipper herb 1 && t_give tipper stick 1 weapon
t_get /inventory
expect_body '<li title="Weapon: Stick" data-tip data-tip-side="left" tabindex="0"><img src="/static/images/icon_weapon.gif" width="15" height="15" alt="Weapon"><span class="invpanel-name">Stick</span><template class="tip"><div class="tip-title">Stick</div><div class="tip-meta">Weapon</div><ul class="tip-lines"><li>Attack Power +2</li></ul></template></li>'
expect_body '<li title="Armor: None" data-tip data-tip-side="left"><img'
t_items_clear tipper

t_section "tips: lore on the help pages"
t_jar tipsout
t_get /help
tp_has '<li>0 +attack spells</li>
</ul>
<div class="help-lore help-lore-class"><p>In the towers of Midworld the old masters'
expect_body '<div class="help-lore help-lore-class"><p>Warriors learn their trade on the long road between Midworld and Roma'
expect_body '<div class="help-lore help-lore-class"><p>The Paladins keep an oath sworn before the first dragon fell'
t_get /help/spells
expect_body '<div class="help-lore"><p>'"$TP_HEAL_LORE"'</p></div></td>'
[ "$(grep -o 'class="help-lore"' "$BODY" | wc -l)" = 1 ] && t_ok || t_fail "only Heal has lore on /help/spells"
t_get /help/items
expect_body '>Herb<br><span class="small">Restores 30 hit points, in a fight or out of it.</span><div class="help-lore"><p>A bitter green leaf'
[ "$(grep -o 'class="help-lore"' "$BODY" | wc -l)" = 1 ] && t_ok || t_fail "only the Herb has lore on /help/items"
t_get /help/monsters
expect_body '<tr class="help-lore-row"><td colspan="9"><div class="help-lore"><p>'"$TP_SLIME_LORE"'</p></div></td></tr>'
[ "$(grep -o 'class="help-lore"' "$BODY" | wc -l)" = 1 ] && t_ok || t_fail "only the Blue Slime has lore on /help/monsters"

t_section "tips: lore overrides, escaped everywhere"
t_jar tipadmin; t_reset_jar; t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/spells/6; expect_status 200
tp_has '<tr><td class="admin-label">Lore:</td><td>
<textarea name="lore" rows="6" cols="40"></textarea>'
expect_body 'Optional story text, shown in tooltips and on the help page'
TP_HURT_DESC=$(t_sql "SELECT description FROM spells WHERE id = 6")
TP_LORE=$(printf 'A <b>bold</b> lie,\nwrapped.\n\n<script>alert(1)</script> & "quoted" '"'"'too'"'"'')
# too long: refused, nothing saved
t_form_submit /admin/spells/6 "description=$TP_HURT_DESC" "lore=$(printf '%2001s' x)"
expect_status 200; expect_body 'Lore must be a string of at most 2000 characters.'
tp_eq "SELECT count(*) FROM content_overrides WHERE kind = 'spells' AND key = 'hurt'" "0" "a too long lore is not saved"
t_get /admin/spells/6
t_form_submit /admin/spells/6 "description=<img src=x onerror=alert(2)>" "lore=$TP_LORE"
expect_redirect '/admin/spells/6\?saved=1'
tp_eq "SELECT group_concat(field) FROM (SELECT field FROM content_overrides WHERE kind = 'spells' AND key = 'hurt' ORDER BY field)" "description,lore" "only description and lore are overridden"
tp_eq "SELECT lore = (SELECT value FROM content_overrides WHERE kind = 'spells' AND key = 'hurt' AND field = 'lore') FROM spells WHERE id = 6" "1" "lore override applied"
tp_eq "SELECT lore FROM spells WHERE id = 6" "$TP_LORE" "lore stored as typed"
t_get '/admin/spells/6?saved=1'
expect_body '&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quoted&quot; &#39;too&#39;</textarea>'
expect_body '<button class="link">Reset Lore to file</button>'
TP_ESCAPED='<div class="tip-body"><p>&lt;img src=x onerror=alert(2)&gt;</p></div><div class="tip-lore"><p>A &lt;b&gt;bold&lt;/b&gt; lie, wrapped.</p><p>&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quoted&quot; &#39;too&#39;</p></div></template></span>'
t_jar tips
t_fight tipper 1 4
t_get /fight
expect_body "$TP_ESCAPED"; expect_no_body '<script>alert(1)'; expect_no_body '<img src=x'
t_fight_clear tipper
t_get /help/spells
expect_body '<div class="help-lore"><p>A &lt;b&gt;bold&lt;/b&gt; lie, wrapped.</p><p>&lt;script&gt;alert(1)&lt;/script&gt;'
expect_no_body '<script>alert(1)'
# reset to the file: no lore again
t_jar tipadmin
t_get /admin/spells/6
t_post /admin/spells/6/reset "csrf=$(t_csrf)&field=lore"
tp_eq "SELECT lore FROM spells WHERE id = 6" "" "lore reset to the file's (none)"
t_get /admin/spells/6; expect_no_body 'Reset Lore to file'; expect_body 'Reset Description to file'
t_post /admin/spells/6/reset "csrf=$(t_csrf)&field=*"
tp_eq "SELECT count(*) FROM content_overrides WHERE kind = 'spells' AND key = 'hurt'" "0" "overrides reset"
tp_eq "SELECT description FROM spells WHERE id = 6" "$TP_HURT_DESC" "description reset"
# a class's lore: the class file's, overridden, then reset
t_get /admin/classes/1
tp_has '<textarea name="lore" rows="6" cols="40">In the towers of Midworld the old masters still teach the words that bend the world: a
whisper that closes wounds'
t_get /admin/monsters/1; expect_body '<textarea name="lore" rows="6" cols="40">The humblest monster of the land'
t_get /admin/items/66;   expect_body '<textarea name="lore" rows="6" cols="40">A bitter green leaf'
t_get /admin/statuses/1; expect_body '<textarea name="lore" rows="6" cols="40"></textarea>'
t_get /admin/summons/1;  expect_body '<textarea name="lore" rows="6" cols="40"></textarea>'

t_section "tips: lore in content files is validated"
TP_FILE="$T/app/content/summons/tipdog.lua"
printf 'return { name = "Tipdog", hp = 3, lore = 42, act = function(a) end }\n' > "$TP_FILE"
"$BIN" check --config "$CONFIG" >"$T/tips.log" 2>&1 && t_fail "dk check passed with a number as lore" || t_ok
grep -qF "summons/tipdog.lua: field 'lore' must be a string of at most 2000 characters" "$T/tips.log" && t_ok || t_fail "lore type error: $(cat "$T/tips.log")"
printf 'return { name = "Tipdog", hp = 3, lore = string.rep("x", 2001), act = function(a) end }\n' > "$TP_FILE"
"$BIN" check --config "$CONFIG" >"$T/tips.log" 2>&1 && t_fail "dk check passed with too long lore" || t_ok
grep -qF "summons/tipdog.lua: field 'lore' must be a string of at most 2000 characters" "$T/tips.log" && t_ok || t_fail "lore length error: $(cat "$T/tips.log")"
printf 'return { name = "Tipdog", hp = 3, lore = string.rep("x", 2000), act = function(a) end }\n' > "$TP_FILE"
"$BIN" check --config "$CONFIG" >"$T/tips.log" 2>&1 && t_ok || t_fail "dk check with 2000 characters of lore: $(cat "$T/tips.log")"
rm -f "$TP_FILE"
"$BIN" check --config "$CONFIG" >"$T/tips.log" 2>&1 && t_ok || t_fail "dk check after removing the file: $(cat "$T/tips.log")"
t_wait_for /help/spells 'Help: Spells' && t_ok || t_fail "help after the content check"
tp_eq "SELECT count(*) FROM summons WHERE key = 'tipdog'" "0" "the test summon never synced"
tp_eq "SELECT coalesce((SELECT value FROM meta WHERE key = 'content_error'), '')" "" "no content error left"
t_jar default

fi
