# tests/e2e/hotbar.sh :: the fight's hotbar (3.1, lib/hotbar.lua; docs/APP.md "Hotbar"):
# the bar filled from what a character has (gear that casts, fight spells, fight
# consumables, in that order) without writing anything on GETs, fixed when a fight begins
# (user_hotbar), the fight page's slots and keys, an action not at hand greyed in its slot,
# the actions off a full bar under More, arranging on /hotbar (save, reset, refusals, not
# while fighting), and new actions finding the first free key at the next fight. The keys
# themselves are pressed in tests/browser/client.js. Sourced by tests/run.sh.

if ! t_has_sql; then
	t_section "hotbar (skipped: needs sqlite3 or python3)"
else

HQ="WHERE username = 'barkeep'"
hb_sql() { t_sql "$1 $HQ"; }
# the stored bar: "kind:ref@slot" (slot "-": off the bar), by kind and id
HB_ROWS="(SELECT group_concat(k, ' ') FROM (SELECT h.kind || ':' || h.ref_id || '@' || coalesce(h.slot, '-') AS k
	FROM user_hotbar h WHERE h.user_id = users.id ORDER BY h.kind DESC, h.ref_id))"
hb_rows() { t_sql "SELECT coalesce($HB_ROWS, '') FROM users $HQ"; }
hb_is() {  # hb_is EXPECTED LABEL: the stored bar
	local got; got=$(hb_rows)
	if [ "$got" = "$1" ]; then t_ok; else t_fail "$2: expected '$1', got '$got'"; fi
}
# the fight page's bar: "n=name=value" per slot with a button, "n=gone" greyed, "n=-" empty
hb_bar() {
	python3 - "$BODY" <<'PY'
import re, sys
body = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<ol class="hotbar-slots">(.*?)</ol>', body, re.S)
out = []
for li in re.findall(r'<li class="hotbar-slot[^"]*"[^>]*>.*?</li>', m.group(1) if m else "", re.S):
	n = re.search(r'<kbd class="hotkey"[^>]*>(\d)</kbd>', li).group(1)
	b = re.search(r'<button class="(?:spell|action)-btn" type="submit" name="(\w+)" value="([^"]*)"', li)
	out.append(n + "=" + (b.group(1) + "=" + b.group(2) if b else "gone" if "hotbar-gone" in li else "-"))
print(" ".join(out))
PY
}
hb_bar_is() {  # hb_bar_is EXPECTED LABEL (on $BODY, a fight page)
	local got; got=$(hb_bar)
	if [ "$got" = "$1" ]; then t_ok; else t_fail "$2: expected '$1', got '$got'"; fi
}
HB_WAND=$(t_sql "SELECT id FROM items WHERE key = 'wand'")

t_section "hotbar: filled from what the character has"
t_jar hotbar; t_reset_jar
t_register barkeep barpw1 barkeep@example.com Barkeep 1
t_login barkeep barpw1; expect_redirect /
hb_sql "UPDATE users SET currenthp = 900, base_maxhp = 900"   # (no ambush ends the tests' fights)
t_get /
expect_body '<a href="/hotbar">Hotbar</a>'
t_spells barkeep 1,6
t_give barkeep herb 2; t_give barkeep wand 1 weapon; t_give barkeep stick 1   # (a stick does nothing in a fight)
t_get /hotbar; expect_status 200; expect_body '<title>Hotbar</title>'
# 1 Attack and 0 Run fixed; the wand (gear first), Heal, Hurt, the Herb on 2-5
expect_body '<li class="hotbar-slot hotbar-fixed"><kbd class="hotkey">1</kbd>'
expect_body '<span class="hotbar-name">Attack</span>'; expect_body '<span class="hotbar-name">Run</span>'
expect_body '<option value="item:'"$HB_WAND"'" selected>Wand (gear)</option>'
expect_body '<select name="slot3" aria-label="Key 3"><option value="">Empty</option>'
expect_body '<option value="spell:1" selected>Heal (spell)</option>'
expect_body '<option value="spell:6" selected>Hurt (spell)</option>'
expect_body '<option value="item:66" selected>Herb (item)</option>'
expect_body 'Herb<span class="small light">Key 5</span>'
expect_no_body 'Stick'
[ "$(grep -o ' selected>' "$BODY" | wc -l)" = 4 ] && t_ok || t_fail "four slots taken"
hb_is "" "a page writes nothing"

t_section "hotbar: fixed when a fight begins"
t_fight_new barkeep; HC=$(t_csrf)
expect_body '<div class="hotbar" role="group" aria-labelledby="hotbar-label">'
hb_is "spell:1@3 spell:6@4 item:66@5 item:$HB_WAND@2" "the encounter settled the bar"
hb_bar_is "1=fight=Fight 2=use_gear=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id $HQ AND ui.equipped = 'weapon'") 3=spell=1 4=spell=6 5=item=66 6=- 7=- 8=- 9=guard=Guard 0=run=Run" "the fight's bar"
expect_body 'aria-label="Heal (5 MP)" aria-keyshortcuts="3"'
expect_body '<li class="hotbar-slot hotbar-empty" aria-hidden="true"><kbd class="hotkey">6</kbd><span class="hotbar-hole"></span></li>'
expect_no_body 'class="fight-more"'
# not while fighting: the bar stays as the fight began
t_get /hotbar; expect_redirect /fight
t_post /hotbar "csrf=$HC&slot2=spell:6"; expect_redirect /fight
hb_is "spell:1@3 spell:6@4 item:66@5 item:$HB_WAND@2" "unchanged while fighting"
# the herbs used up: the slot stays, greyed, with the herb's tooltip and why
t_items_clear barkeep; t_give barkeep wand 1 weapon
t_get /fight
hb_bar_is "1=fight=Fight 2=use_gear=$(t_sql "SELECT min(ui.id) FROM user_items ui JOIN users u ON u.id = ui.user_id $HQ AND ui.equipped = 'weapon'") 3=spell=1 4=spell=6 5=gone 6=- 7=- 8=- 9=guard=Guard 0=run=Run" "a used-up item keeps its key"
expect_body '<span class="spell-btn" role="img" title="Herb (none left)" aria-label="Herb (none left)"><img src="/static/images/items/herb.png" width="44" height="44" alt=""></span><template class="tip"><div class="tip-title"><img class="tip-icon"'
# the wand taken off: its slot greyed as "not worn"
t_items_clear barkeep
t_get /fight; expect_body 'title="Wand (not worn)"'; expect_no_body 'name="use_gear"'
t_fight_clear barkeep; hb_sql "UPDATE users SET currentaction = 'Exploring'"

t_section "hotbar: arranging"
t_give barkeep herb 2; t_give barkeep wand 1 weapon
t_get /hotbar
# the actions not at hand are still choices while they hold a key (a used-up herb: kept)
expect_body 'Wand<span class="small light">Key 2</span>'
t_post /hotbar "slot2=spell:6"; expect_status 403
# Hurt on 2, Heal on 8, the wand off the bar, 3-7 empty; the herb not chosen: off the bar
# (9 is Guard's: a list for it is no slot)
t_post /hotbar "csrf=$HC&slot2=spell:6&slot3=&slot8=spell:1&slot9=item:66&save=Save"; expect_redirect '/hotbar\?saved=1'
hb_is "spell:1@8 spell:6@2 item:66@- item:$HB_WAND@-" "saved"
t_get '/hotbar?saved=1'; expect_body '<p class="hotbar-note" role="status">Your hotbar is saved.</p>'
expect_body '<li class="hotbar-slot hotbar-fixed"><kbd class="hotkey">9</kbd><span class="action-btn"><img src="/static/images/skills/guard.png" width="44" height="44" alt=""></span><span class="hotbar-name">Guard</span></li>'
expect_no_body 'name="slot9"'
expect_body 'Wand<span class="small light">Not on the bar</span>'
# the same action twice (no JavaScript): the first key keeps it
t_post /hotbar "csrf=$HC&slot4=spell:1&slot7=spell:1&slot5=item:66"; expect_redirect '/hotbar\?saved=1'
hb_is "spell:1@4 spell:6@- item:66@5 item:$HB_WAND@-" "the first of two"
# an action the character doesn't have, or not a key at all: refused, nothing changes
t_post /hotbar "csrf=$HC&slot2=spell:7"; expect_body 'Cheat attempt detected.'
t_post /hotbar "csrf=$HC&slot2=item:67"; expect_body 'Cheat attempt detected.'
t_post /hotbar "csrf=$HC&slot2=$(t_enc "spell:1 OR 1=1")"; expect_body 'Cheat attempt detected.'
hb_is "spell:1@4 spell:6@- item:66@5 item:$HB_WAND@-" "refusals change nothing"
# in the fight: the bar as saved, the actions off it under More (without keys)
t_fight_new barkeep
hb_is "spell:1@4 spell:6@- item:66@5 item:$HB_WAND@-" "the next fight keeps the arrangement"
hb_bar_is "1=fight=Fight 2=- 3=- 4=spell=1 5=item=66 6=- 7=- 8=- 9=guard=Guard 0=run=Run" "the saved bar"
expect_body '<div class="fight-more" role="group" aria-labelledby="fight-more-label"><span class="fight-more-label" id="fight-more-label">More</span>'
expect_body 'name="use_gear" value="'; expect_body 'title="Hurt (5 MP)" aria-label="Hurt (5 MP)"><img'   # no key
t_fight_clear barkeep; hb_sql "UPDATE users SET currentaction = 'Exploring'"
# reset: the arrangement forgotten, the bar fills again (written at the next fight)
t_post /hotbar "csrf=$HC&forget=Reset"; expect_redirect '/hotbar\?reset=1'
hb_is "" "reset"
t_get '/hotbar?reset=1'; expect_body 'Your hotbar is back to its first arrangement'
expect_body '<option value="item:'"$HB_WAND"'" selected>Wand (gear)</option>'

t_section "hotbar: new actions take the first free key"
t_post /hotbar "csrf=$HC&slot2=spell:1&slot3=spell:6"
t_fight_new barkeep
hb_is "spell:1@2 spell:6@3 item:66@- item:$HB_WAND@-" "saved before the fight"
t_fight_clear barkeep; hb_sql "UPDATE users SET currentaction = 'Exploring'"
# learned since: Pain, Maim, Rend, Chaos, Sleep, Dream, Nightmare (7 more for 5 free keys)
t_spells barkeep 1,6,7,8,9,10,11,12,13
t_get /hotbar
expect_body '<option value="spell:7" selected>Pain (spell)</option>'
expect_body 'Nightmare<span class="small light">Not on the bar</span>'
t_fight_new barkeep
hb_is "spell:1@2 spell:6@3 spell:7@4 spell:8@5 spell:9@6 spell:10@7 spell:11@8 spell:12@- spell:13@- item:66@- item:$HB_WAND@-" \
	"the free keys filled, the last one off the bar"
hb_bar_is "1=fight=Fight 2=spell=1 3=spell=6 4=spell=7 5=spell=8 6=spell=9 7=spell=10 8=spell=11 9=guard=Guard 0=run=Run" "a full bar"
expect_body 'title="Nightmare ('   # under More
t_fight_clear barkeep; hb_sql "UPDATE users SET currentaction = 'Exploring'"
# a key freed later stays free: an action off the bar was met, it doesn't jump on
t_post /hotbar "csrf=$HC&slot2=spell:1"
t_fight_new barkeep
hb_is "spell:1@2 spell:6@- spell:7@- spell:8@- spell:9@- spell:10@- spell:11@- spell:12@- spell:13@- item:66@- item:$HB_WAND@-" \
	"met actions stay off the bar"
t_fight_clear barkeep; hb_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"
t_items_clear barkeep

fi
