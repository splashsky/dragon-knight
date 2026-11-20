# tests/e2e/tips.sh :: tooltips and lore (docs/APP.md "Tooltips", "Lore"): tooltip.js on
# every layout; the tooltip templates of the fight menu's spell buttons (name, MP, where it
# can be cast, description, lore; disabled buttons too), of the monster fought, of Fast
# Spells, of the fight menu's Attack and Run buttons (attack power, weapon; the locked
# "Continue" turn unchanged), of the registration page's classes and in the JSON fight
# fragments; item tooltips on the Inventory page, in the shop (list, purchase page, Sell
# list) and on the discard page (escaped admin overrides, lore); lore on the
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
expect_body 'The classes: <span class="tip-term" data-tip data-tip-side="bottom" tabindex="0">Mage<template class="tip"><div class="tip-title">Mage</div><div class="tip-meta">Starts with 15 HP, 5 MP · Knows Magic Bolt</div><ul class="tip-lines"><li>Fast level-ups</li><li>High hit points</li>'
expect_body '<li>0 +attack spells</li></ul><div class="tip-lore"><p>In the towers of Midworld the old masters still teach the words that bend the world: a whisper that closes wounds, a cry that calls down fire. Mages are frail in a brawl, and every adventurer they have saved will tell you so. Few of them mind.</p></div></template></span>'
expect_body '>Warrior<template class="tip"><div class="tip-title">Warrior</div><div class="tip-meta">Starts with 15 HP, 0 MP</div>'
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
# a live answer's regions are the same templates (the live client morphs them in as they are)
if command -v python3 >/dev/null; then
	t_live_forget; t_live GET /fight; expect_status 200
	w_payload region root > "$T/tips_root.html"
	python3 - "$T/tips_root.html" "$TP_HEAL_LORE" <<'PY' && t_ok || t_fail "live regions without the tooltips"
import re, sys
body = open(sys.argv[1], encoding="utf-8").read()
main = re.search(r'<main class="dk-middle" data-r="main"[^>]*>(.*?)</main>', body, re.S).group(1)
right = re.search(r'<aside class="dk-right" data-r="right"[^>]*>(.*?)</aside>', body, re.S).group(1)
assert '<span class="spell-tip" data-tip><button class="spell-btn" type="submit" name="spell" value="1"' in main
assert '<div class="tip-lore"><p>' + sys.argv[2] + '</p></div></template></span>' in main
assert '>Blue Slime<template class="tip"><div class="tip-title">Blue Slime</div><div class="tip-meta">Level 1</div>' in main
assert 'data-tip data-tip-side="left"><input type="hidden" name="csrf"' in right and '<div class="tip-title">Heal</div>' in right
assert '<span class="action-tip" data-tip><button class="action-btn" type="submit" name="fight" value="Fight"' in main
assert '<div class="tip-title">Attack</div><div class="tip-meta">Attack Power ' in main and '<div class="tip-title">Run</div>' in main
PY
fi

t_section "tips: the fight menu's actions"
# Attack and Run are icon buttons (fight=Fight, run=Run, as the old text buttons sent) in
# spans that carry their tooltips; Attack's says the attack power (strength + base attack +
# the weapon's) and the weapon. The order: Attack, the equipped gear's abilities, Run, the
# spells, the items.
t_sql "UPDATE users SET strength = 10, base_attack = 3 WHERE username = 'tipper'"
t_get /fight
expect_body '<div class="fight-actions" role="group" aria-labelledby="fight-actions-label"><span class="fight-actions-label" id="fight-actions-label">Actions</span>'
expect_body '<span class="action-tip" data-tip><button class="action-btn" type="submit" name="fight" value="Fight" title="Attack" aria-label="Attack"><img src="/static/images/skills/attack.png" width="44" height="44" alt=""></button><template class="tip"><div class="tip-title">Attack</div><div class="tip-meta">Attack Power 13</div><div class="tip-body"><p>Strike the monster with your weapon.</p></div></template></span>'
expect_body '<span class="action-tip action-run" data-tip><button class="action-btn" type="submit" name="run" value="Run" title="Run" aria-label="Run"><img src="/static/images/skills/run.png" width="44" height="44" alt=""></button><template class="tip"><div class="tip-title">Run</div><div class="tip-body"><p>Try to escape. The monster may block your way and strike.</p></div></template></span>'
expect_no_body '<input type="submit" name="fight"'; expect_no_body '<input type="submit" name="run"'
t_give tipper stick 1 weapon
t_get /fight; expect_body '<div class="tip-title">Attack</div><div class="tip-meta">Attack Power 15 · Stick</div>'
t_items_clear tipper; t_give tipper wand 1 weapon; t_give tipper herb 1
t_get /fight
TP_ORDER=$(grep -o 'name="fight"\|name="run"\|name="spell"\|name="use_gear"\|name="item"' "$BODY" | uniq | tr '\n' ' ')
[ "$TP_ORDER" = 'name="fight" name="use_gear" name="run" name="spell" name="item" ' ] && t_ok || t_fail "fight menu order: $TP_ORDER"
# the wand's button: its picture, the charges as a badge, a tooltip with the spell
expect_body '<span class="spell-tip" data-tip><button class="spell-btn" type="submit" name="use_gear" value="'
expect_body '" title="Wand (5/5 charges)" aria-label="Wand (5/5 charges)"><img src="/static/images/items/wand.png" width="44" height="44" alt=""><span class="item-badge item-badge-charges" aria-hidden="true">5/5</span></button><template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/items/wand.png" width="20" height="20" alt="">Wand</div><div class="tip-meta">Casts Magic Bolt · Charges 5/5 · No MP</div><ul class="tip-lines"><li>Magic Bolt: Hurls a small bolt of force at the monster, whatever its armor. Some monsters are immune.</li></ul><div class="tip-body"><p>A short rod'
expect_body '<div class="tip-title">Attack</div><div class="tip-meta">Attack Power 15 · Wand</div>'
t_get /static/images/skills/attack.png; expect_status 200; expect_header '^content-type: image/png'
t_get /static/images/skills/run.png;    expect_status 200; expect_header '^content-type: image/png'
# a turn a status blocks: only the "Continue" text button, as before
t_fight_status tipper 1 recharging '' 1
t_get /fight
expect_body '<p><input type="submit" name="continue" value="Continue"></p>'
expect_no_body 'class="action-btn"'; expect_no_body 'fight-actions'; expect_no_body 'name="run"'
t_items_clear tipper
t_fight_clear tipper

t_section "tips: the inventory panel's gear"
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 WHERE username = 'tipper'"
t_give tipper herb 1 && t_give tipper stick 1 weapon
t_get /inventory
expect_body '<li title="Weapon: Stick" data-tip data-tip-side="left" tabindex="0"><img src="/static/images/icon_weapon.gif" width="15" height="15" alt="Weapon"><span class="invpanel-name">Stick</span><template class="tip"><div class="tip-title">Stick</div><div class="tip-meta">Weapon</div><ul class="tip-lines"><li>Attack Power +2</li></ul></template></li>'
expect_body '<li title="Armor: None" data-tip data-tip-side="left"><img'
# an item with a picture shows it instead of the slot's icon; its tooltip says its charges
t_items_clear tipper; t_give tipper wand 1 weapon
t_sql "UPDATE user_items SET charges = 2 WHERE user_id = (SELECT id FROM users WHERE username = 'tipper')"
t_get /inventory
expect_body '<li title="Weapon: Wand" data-tip data-tip-side="left" tabindex="0"><img class="invpanel-image" src="/static/images/items/wand.png" width="17" height="17" alt="Weapon"><span class="invpanel-name">Wand</span><template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/items/wand.png" width="20" height="20" alt="">Wand</div><div class="tip-meta">Weapon</div><ul class="tip-lines"><li>Attack Power +2</li><li>Casts Magic Bolt</li><li>Charges 2/5</li></ul>'
t_items_clear tipper

t_section "tips: items on the Inventory page, in the shop and when discarding"
# The Branch gets an XSS description and lore (admin overrides; reset below): escaped
# wherever its tooltip shows. The Herb shows its starter lore.
t_jar tipadmin; t_reset_jar; t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/items/2
t_form_submit /admin/items/2 "description=<img src=x onerror=alert(3)>" "lore=$(printf '<script>alert(4)</script> & "q"')"
expect_redirect '/admin/items/2\?saved=1'
TP_BRANCH='>Branch<template class="tip"><div class="tip-title">Branch</div><div class="tip-meta">Weapon</div><ul class="tip-lines"><li>Attack Power +4</li></ul><div class="tip-body"><p>&lt;img src=x onerror=alert(3)&gt;</p></div><div class="tip-lore"><p>&lt;script&gt;alert(4)&lt;/script&gt; &amp; &quot;q&quot;</p></div></template>'
TP_HERB='>Herb<template class="tip"><div class="tip-title"><img class="tip-icon" src="/static/images/items/herb.png" width="20" height="20" alt="">Herb</div><div class="tip-meta">Consumable · In fights and in town</div><ul class="tip-lines"><li>Power 30</li></ul><div class="tip-body"><p>Restores 30 hit points, in a fight or out of it.</p></div><div class="tip-lore"><p>A bitter green leaf that grows wild along the roads around Midworld.'
TP_STICK='>Stick<template class="tip"><div class="tip-title">Stick</div><div class="tip-meta">Weapon</div><ul class="tip-lines"><li>Attack Power +2</li></ul></template>'
tp_no_xss() { expect_no_body '<script>alert(4)'; expect_no_body '<img src=x'; }
t_jar tips
t_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0, gold = 1000 WHERE username = 'tipper'"
t_give tipper stick 1 weapon && t_give tipper herb 3 && t_give tipper branch 1
TP_HERB_E=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'tipper' AND ui.item_id = 66")
TP_BRANCH_E=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id WHERE u.username = 'tipper' AND ui.item_id = 2")
# /inventory: the equipped slots and every bag entry (focusable names), the actions as before
t_get /inventory; expect_status 200
expect_body '<td><b class="tip-term" data-tip tabindex="0"'"$TP_STICK"'</b> <span class="small">(Attack Power +2)</span></td>'
expect_body '<img class="inv-icon" src="/static/images/items/herb.png" width="32" height="32" alt="">'
expect_body '<b class="tip-term" data-tip tabindex="0"'"$TP_HERB"; expect_body '</p></div></template></b> x3'
expect_body '<img class="inv-icon" src="/static/images/skills/default.png" width="32" height="32" alt="">'   # the Branch
expect_body '<b class="tip-term" data-tip tabindex="0"'"$TP_BRANCH"'</b>'; tp_no_xss
expect_body "action=\"/inventory/equip/$TP_BRANCH_E\""; expect_body "action=\"/inventory/use/$TP_HERB_E\""
expect_body "href=\"/inventory/discard/$TP_HERB_E\">Discard</a>"; expect_body 'action="/inventory/unequip/weapon"'
# the shop: the links carry their tooltip (no tabindex: a link is focusable), the item
# worn is for sale too (2.4), and the Sell list's names are focusable terms
t_get /shop; expect_status 200
expect_body 'href="/shop/buy/2" data-tip'"$TP_BRANCH"'</a>'; tp_no_xss
expect_body 'href="/shop/buy/66" data-tip'"$TP_HERB"
expect_body 'href="/shop/buy/1" data-tip'"$TP_STICK"'</a>'; expect_no_body 'Already purchased'
expect_body '<td class="shop-icon"><img class="item-icon" src="/static/images/items/herb.png" width="22" height="22" alt=""></td>'
expect_body '<td class="shop-icon"><img src="/static/images/icon_weapon.gif" alt="weapon"></td>'
expect_body '<tr><td><img class="item-icon" src="/static/images/items/herb.png" width="22" height="22" alt=""> <span class="tip-term" data-tip tabindex="0"'"$TP_HERB"; expect_body '</p></div></template></span> x3</td><td>8 gold each</td>'
expect_body '<tr><td><span class="tip-term" data-tip tabindex="0"'"$TP_BRANCH"'</span></td><td>15 gold</td>'
# the purchase page: the item bought and the one it replaces
t_get /shop/buy/2; expect_status 200
expect_body 'You are buying the <span class="tip-term" data-tip tabindex="0"'"$TP_BRANCH"'</span> for 30 gold. What should I do with your <span class="tip-term" data-tip tabindex="0"'"$TP_STICK"'</span>?'
expect_text 'You are buying the Branch for 30 gold. What should I do with your Stick?'; tp_no_xss
expect_no_body 'shop-buy-icon'
t_get /shop/buy/66
expect_body '<img class="shop-buy-icon" src="/static/images/items/herb.png" width="44" height="44" alt="">'
expect_body 'You are buying the <span class="tip-term" data-tip tabindex="0"'"$TP_HERB"
expect_text 'You are buying the Herb for 15 gold each. It goes into your bag.'
# the discard confirmation
t_get "/inventory/discard/$TP_HERB_E"
expect_body 'You have 3 x <span class="tip-term" data-tip tabindex="0"'"$TP_HERB"
expect_text 'You have 3 x Herb. How many do you want to throw away?'
t_get "/inventory/discard/$TP_BRANCH_E"
expect_body 'Do you really want to throw away the <span class="tip-term" data-tip tabindex="0"'"$TP_BRANCH"'</span>? It will be gone for good.'; tp_no_xss
t_items_clear tipper
t_jar tipadmin
t_get /admin/items/2
t_post /admin/items/2/reset "csrf=$(t_csrf)&field=*"
tp_eq "SELECT count(*) FROM content_overrides WHERE kind = 'items' AND key = 'branch'" "0" "branch overrides reset"
tp_eq "SELECT coalesce(description, '') || '|' || coalesce(lore, '') FROM items WHERE id = 2" "|" "branch description and lore reset"
t_jar tips

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
[ "$(grep -o 'class="help-lore"' "$BODY" | wc -l)" = 2 ] && t_ok || t_fail "only Heal and Magic Bolt have lore on /help/spells"
t_get /help/items
expect_body '>Herb<br><span class="small">Restores 30 hit points, in a fight or out of it.</span><div class="help-lore"><p>A bitter green leaf'
[ "$(grep -o 'class="help-lore"' "$BODY" | wc -l)" = 2 ] && t_ok || t_fail "only the Herb and the Wand have lore on /help/items"
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
