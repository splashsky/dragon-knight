# tests/e2e/fight_api.sh :: the JSON fight API and smooth fights (2.3, docs/APP.md "Fight
# API"): the same scenarios played as a form and with fetch from the same state and the
# same dice (X-Test-Seed, test_routes) must leave the same database and say the same lines;
# the events' shape (spells, items, statuses, summons, monster spells and items); stale
# rounds (a second click, an older tab) in both paths; CSRF; the victory, death and drop
# pages as fragments; the no-JS page (the round field, fight.js only on fight pages).
# Sourced by tests/run.sh.
if ! command -v python3 >/dev/null; then
	t_section "fight api (skipped: needs python3)"
else

t_section "fight api: setup"
t_jar fightapi
t_register fapi fapipw1 fapi@example.com Fapi 1
t_login fapi fapipw1
FAQ="WHERE username = 'fapi'"
fa_sql() { t_sql "$1 $FAQ"; }
fa_is() {  # fa_is EXPR EXPECTED (an SQL expression on the users row)
	local got; got=$(t_sql "SELECT $1 FROM users $FAQ")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$1: expected '$2', got '$got'"; fi
}
sp() { t_sql "SELECT id FROM spells WHERE key = '$1'"; }
it() { t_sql "SELECT id FROM items WHERE key = '$1'"; }
mon() { t_sql "SELECT id FROM monsters WHERE key = '$1'"; }
t_spells fapi "$(sp heal),$(sp hurt),$(sp sleep),$(sp poison),$(sp regen),$(sp hyper_beam),$(sp solar_beam),$(sp call_wolf)"

# Everything a round may change, as one line: the player's numbers, the fight, its
# combatants and statuses, the bag.
FA_STATE="SELECT currenthp || ',' || currentmp || ',' || currenttp || ',' || gold || ',' || experience || ',' ||
	currentaction || ',' || latitude || ',' || longitude || ',' || dropcode || '|' || $T_ROUND || '|' ||
	coalesce((SELECT wave || ':' || replace(data, char(10), ';') FROM fights f WHERE f.user_id = users.id), '') || '|' ||
	coalesce((SELECT group_concat(k, ' ') FROM (SELECT c.id || ':' || c.side || ':' || c.kind || ':' || coalesce(c.entity_id, '') || ':' ||
		coalesce(c.hp, '') || '/' || coalesce(c.maxhp, '') || ':' || coalesce(c.mp, '') || ':' || coalesce(c.turns_left, '') || ':' ||
		replace(c.data, char(10), ';') AS k FROM fight_combatants c WHERE c.user_id = users.id ORDER BY c.id)), '') || '|' ||
	coalesce((SELECT group_concat(k, ' ') FROM (SELECT fs.combatant_id || ':' || fs.status_id || ':' || coalesce(fs.turns_left, '') || ':' ||
		replace(fs.data, char(10), ';') || ':' || fs.applied_round || ':' || coalesce(fs.source, '') AS k
		FROM fight_statuses fs WHERE fs.user_id = users.id ORDER BY fs.combatant_id, fs.position)), '') || '|' ||
	coalesce($T_ITEMS, '') FROM users $FAQ"
fa_state() { t_sql "$FA_STATE"; }

# JSON and HTML helpers (python3): the fight lines of a page, the events' texts, a value
# of the answer (an expression on d), and the shape of the answer and its events.
cat > "$T/fa.py" <<'PY'
import html, json, re, sys

cmd, path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()

ACTORS = {"player", "ally", "enemy"}
TYPES = {"attack", "spell", "item", "status", "summon", "blocked", "run", "ambush", "wave", "say",
	"victory", "death", "escape"}
PARTS = {"player", "allies", "enemies", "ending"}
EVENT = {"part", "actor", "actor_id", "actor_name", "type", "text", "hp", "mp", "tp", "status", "summon"}
CHANGE = {"who", "id", "name", "from", "to", "max"}
STATUS = {"who", "id", "name", "key", "status", "turns", "change", "statuses"}
SUMMON = {"change", "id", "name", "hp", "max", "turns"}
TOP = {"events", "fragments", "round", "redirect", "url", "title", "stale", "error"}
FRAGMENTS = {"main", "nav_left", "nav_right"}

def is_int(v):
	return isinstance(v, int) and not isinstance(v, bool)

def check(d):
	assert isinstance(d, dict), "not an object"
	assert set(d) <= TOP, "top-level keys: %s" % sorted(set(d) - TOP)
	if "error" in d:
		assert isinstance(d["error"], str) and d["error"], "error"
		return
	assert isinstance(d.get("events"), list), "events"
	for k in ("redirect", "url", "title"):
		assert k not in d or isinstance(d[k], str), k
	assert "round" not in d or is_int(d["round"]), "round"
	assert "stale" not in d or d["stale"] is True, "stale"
	if "fragments" in d:
		assert set(d["fragments"]) <= FRAGMENTS and "main" in d["fragments"], "fragments"
		assert all(isinstance(v, str) for v in d["fragments"].values()), "fragment strings"
		assert "url" in d and "title" in d, "a page has its url and title"
	else:
		assert "redirect" in d, "fragments or a redirect"
	for e in d["events"]:
		assert set(e) <= EVENT, "event keys: %s" % sorted(set(e) - EVENT)
		assert e["type"] in TYPES, "type %r" % e["type"]
		assert "actor" not in e or e["actor"] in ACTORS, "actor"
		assert "actor" not in e or (is_int(e["actor_id"]) and isinstance(e["actor_name"], str)), "actor id, name"
		assert "part" not in e or e["part"] in PARTS, "part"
		assert "text" not in e or (isinstance(e["text"], str) and e["text"]), "text"
		if e["type"] in ("victory", "death", "escape"):
			assert "text" not in e and e["actor"] == "player", "an outcome"
		else:
			assert e.get("part") in PARTS, "a round's event has its part"
			assert "text" in e or any(k in e for k in ("hp", "mp", "tp", "status", "summon")), "an empty event"
		for k in ("hp", "mp", "tp"):
			for c in e.get(k, None) or []:
				assert set(c) <= CHANGE and c["who"] in ACTORS, "%s change %r" % (k, c)
				assert all(is_int(c[x]) for x in ("id", "from", "to", "max")), "%s numbers %r" % (k, c)
			assert k not in e or e[k], "empty %s list" % k
		for s in e.get("status", []):
			assert set(s) <= STATUS and s["who"] in ACTORS, "status %r" % s
			assert s["change"] in ("add", "remove", "expire", "turns"), "status change %r" % s
			assert isinstance(s["key"], str) and isinstance(s["status"], str), "status names"
			for x in s["statuses"]:
				assert set(x) <= {"key", "name", "turns"}, "statuses %r" % x
		for s in e.get("summon", []):
			assert set(s) <= SUMMON and s["change"] in ("join", "leave", "turns"), "summon %r" % s

if cmd == "lines-html":
	for p in re.findall(r'<p class="fight-(?:yourturn|allyturn|monsterturn|roundend)">(.*?)</p>', text, re.S):
		for line in p.split("<br>"):
			print(html.unescape(line))
elif cmd == "lines-json":
	for e in json.loads(text)["events"]:
		if "text" in e:
			print(e["text"])
elif cmd == "get":
	d = json.loads(text)
	v = eval(sys.argv[3], {"d": d, "any": any, "all": all, "len": len})
	print(v if isinstance(v, str) else json.dumps(v))
elif cmd == "check":
	try:
		check(json.loads(text))
		print("ok")
	except Exception as err:
		print("bad: %s" % err)
elif cmd == "html-has":
	print("yes" if sys.argv[3] in html.unescape(text) else "no")
PY
fa_py() { python3 "$T/fa.py" "$1" "$BODY" "${@:2}"; }
fa_get() { fa_py get "$1"; }
fa_check() {  # the answer (JSON) has the documented shape
	local r; r=$(fa_py check)
	if [ "$r" = ok ]; then t_ok; else t_fail "JSON shape: $r"; fi
}
fa_expect() {  # fa_expect 'python expression on d' [label]: true
	local r; r=$(fa_get "$1")
	if [ "$r" = true ]; then t_ok; else t_fail "${2:-$1}: got $r"; fi
}
fa_location() { grep -i '^location:' "$HEADERS" | tr -d '\r' | cut -d' ' -f2; }

# fa_both LABEL SEED SETUP 'fields': SETUP, then the round as a form (no JS), then SETUP
# again and the same round with fetch, both with the dice seeded by SEED. Same database
# afterwards, same lines (a redirect: the same target), and a well-formed answer. The
# JSON answer stays in $BODY; FA_LINES has its lines.
fa_both() {
	local label=$1 seed=$2 setup=$3 fields=$4 st1 st2 l1 l2 s1 loc1
	$setup
	t_post /fight "csrf=$FA_CS&$fields" -H "X-Test-Seed: $seed"
	s1=$STATUS; st1=$(fa_state); l1=$(fa_py lines-html); loc1=$(fa_location)
	$setup
	t_fetch /fight "$fields" -H "X-Test-Seed: $seed"
	expect_status 200; fa_check
	st2=$(fa_state); l2=$(fa_py lines-json)
	FA_LINES=$l2
	if [ "$st1" = "$st2" ]; then t_ok; else t_fail "$label (seed $seed): the database differs: form $st1, fetch $st2"; fi
	if [ "$s1" = 302 ]; then
		[ "$(fa_get 'd.get("redirect", "")')" = "$loc1" ] && t_ok || t_fail "$label (seed $seed): redirect $loc1 vs $(fa_get 'd.get("redirect")')"
	else
		[ "$s1" = 200 ] && t_ok || t_fail "$label (seed $seed): form status $s1"
		if [ "$l1" = "$l2" ]; then t_ok; else t_fail "$label (seed $seed): the lines differ: form [$l1], fetch [$l2]"; fi
		[ -n "$(fa_get 'd.get("redirect", "")')" ] && t_fail "$label (seed $seed): a redirect" || t_ok
	fi
}

# the player: level 10 Mage, sturdy, no gear, at 30N (fights against given monsters)
fa_player() {
	t_items_clear fapi
	fa_sql "UPDATE users SET level = 10, currenthp = 300, base_maxhp = 300, currentmp = 100, base_maxmp = 100,
		currenttp = 10, base_maxtp = 10, strength = 30, dexterity = 30, base_attack = 0, base_defense = 0,
		base_exp_bonus = 0, base_gold_bonus = 0, gold = 500, experience = 5000, dropcode = 0, latitude = 30, longitude = 0"
}
t_get /fight; FA_CS=$(t_csrf); expect_body 'Cheat attempt detected.'

t_section "fight api: the no-JS page"
fa_player
t_fight fapi 2 50
t_get /fight; expect_status 200
expect_body '<script src="/static/js/fight.js" defer></script>'
expect_body '<input type="hidden" name="round" value="3">'; fa_is "$T_ROUND" 3
expect_body 'action="/fight" method="post" data-fight>'
expect_body "Monster's HP: 50"; expect_no_body 'fight-stale'
expect_body '<div class="dk-nav-right" data-nav-right>'; expect_body 'data-bar="hp"'
t_get /;   expect_redirect /fight
t_sql "UPDATE users SET currentaction = 'In Town' $FAQ"
t_get /;   expect_status 200; expect_no_body 'fight.js'
t_sql "UPDATE users SET currentaction = 'Fighting' $FAQ"
t_get /static/js/fight.js; expect_status 200; expect_body 'data-fight'
if command -v node >/dev/null; then
	node --check "$ROOT/public/js/fight.js" && t_ok || t_fail "fight.js: syntax"
fi
# a form from before 2.3 (no round field) still plays
t_fight fapi 2 50
t_post /fight "csrf=$FA_CS&fight=Fight"; expect_status 200; expect_body 'You attack the monster for'
fa_is "$T_ROUND" 3

t_section "fight api: attacks, form and fetch alike"
fa_slime() { fa_player; t_fight fapi 2 50; }   # a Red Slime
FA_HIT=
for seed in 1 2 3 4 5 6; do
	fa_both attack "$seed" fa_slime "fight=Fight&round=2"
	[ "$(fa_get 'any(e["type"] == "attack" and e["actor"] == "player" and e["hp"][0]["who"] == "enemy" and e["hp"][0]["to"] < e["hp"][0]["from"] for e in d["events"] if "hp" in e)')" = true ] && FA_HIT=1
done
[ -n "$FA_HIT" ] && t_ok || t_fail "no attack's damage in the events"
fa_expect 'd["round"] == 3 and d["url"] == "/fight" and d["title"] == "Fighting"'
fa_expect '"data-player-stats" in d["fragments"]["nav_right"] and "action=\"/move\"" in d["fragments"]["nav_left"]'
fa_expect '"name=\"round\" value=\"3\"" in d["fragments"]["main"] and "<html" not in d["fragments"]["main"]'
fa_expect 'not any("data" in e or "step" in e for e in d["events"])' "no internal state"
# the winning blow: the same redirect, and with fetch its lines too
fa_win() { fa_player; t_fight fapi 2 1; fa_sql "UPDATE users SET base_attack = 500"; }
fa_both victory 7 fa_win "fight=Fight&round=2"
fa_expect 'd["redirect"] == "/victory" and d["events"][-1]["type"] == "victory"'
fa_expect 'any(e["text"].startswith("You attack the monster for") and e["hp"][0]["to"] <= 0 for e in d["events"] if "hp" in e)'
fa_is "$T_MONSTER_HP <= 0" 1

t_section "fight api: the victory page as a fragment"
t_get /victory -H 'Accept: application/json'; expect_status 200; fa_check
fa_expect '"Congratulations. You have defeated the Red Slime." in d["fragments"]["main"] and d["url"] == "/victory"'
fa_expect 'd["title"] in ("Victory!", "Courage and Wit have served thee well!") and d["events"] == []'
fa_is currentaction Exploring; fa_is "$T_ROUND" 0
t_get /victory -H 'Accept: application/json'; fa_check; fa_expect 'd["redirect"] == "/"' "paid once"

t_section "fight api: running away"
fa_run() { fa_player; t_fight fapi 2 50; }
for seed in 1 2 3; do fa_both run "$seed" fa_run "run=Run&round=2"; done
fa_blocked() { fa_player; t_fight fapi 151 30000; fa_sql "UPDATE users SET dexterity = 0"; }
fa_both "blocked run" 4 fa_blocked "run=Run&round=2"
fa_expect 'd["events"][0]["type"] == "run" and d["events"][0]["text"] == "You tried to run away, but were blocked in front!"'
fa_escape() { fa_player; t_fight fapi 2 50; fa_sql "UPDATE users SET dexterity = 10000"; }
fa_both escape 5 fa_escape "run=Run&round=2"
fa_expect 'd["redirect"] == "/" and [e["type"] for e in d["events"]] == ["escape"]'

t_section "fight api: the Attack and Run buttons, form and fetch alike"
# Attack and Run are icon buttons (2.4) sending what the text buttons sent: fight.js
# appends the pressed button's name and value, as a native submit does. The fields come
# from the page's buttons; each plays the same round both ways.
fa_button() {  # fa_button NAME: the name=value the page's action button NAME sends
	grep -o "<button class=\"action-btn\" type=\"submit\" name=\"$1\" value=\"[^\"]*\"" "$BODY" | sed 's/.* name="\([^"]*\)" value="\([^"]*\)"$/\1=\2/'
}
fa_slime; t_get /fight
FA_ATTACK=$(fa_button fight); FA_RUN=$(fa_button run)
[ "$FA_ATTACK" = "fight=Fight" ] && t_ok || t_fail "Attack sends '$FA_ATTACK'"
[ "$FA_RUN" = "run=Run" ] && t_ok || t_fail "Run sends '$FA_RUN'"
for seed in 1 2; do fa_both "attack button" "$seed" fa_slime "$FA_ATTACK&round=2"; done
fa_expect 'any(e["type"] == "attack" and e["actor"] == "player" for e in d["events"])' "Attack button: an attack"
fa_expect "'name=\"fight\" value=\"Fight\" title=\"Attack\" aria-label=\"Attack\"><img src=\"/static/images/skills/attack.png\"' in d['fragments']['main'] and 'name=\"run\" value=\"Run\" title=\"Run\" aria-label=\"Run\"><img src=\"/static/images/skills/run.png\"' in d['fragments']['main']" "the fragment's action buttons"
fa_both "attack button, victory" 7 fa_win "$FA_ATTACK&round=2"
fa_expect 'd["redirect"] == "/victory"'
fa_both "run button, blocked" 4 fa_blocked "$FA_RUN&round=2"
fa_expect 'd["events"][0]["type"] == "run"'
fa_both "run button, escape" 5 fa_escape "$FA_RUN&round=2"
fa_expect 'd["redirect"] == "/" and [e["type"] for e in d["events"]] == ["escape"]'

t_section "fight api: spells and items"
fa_hurt() { fa_player; fa_sql "UPDATE users SET currenthp = 150"; t_fight fapi 2 50; }
for seed in 1 2; do fa_both heal "$seed" fa_hurt "spell=Spell&userspell=$(sp heal)&round=2"; done
fa_expect 'any(e["type"] == "spell" and e["actor"] == "player" and e["text"].startswith("You have cast the Heal spell") and e["hp"][0]["who"] == "player" and e["hp"][0]["to"] > e["hp"][0]["from"] and e["mp"][0]["from"] - e["mp"][0]["to"] == 5 for e in d["events"] if "hp" in e and "mp" in e)' "Heal: HP and MP"
for seed in 3 4; do fa_both hurt "$seed" fa_slime "spell=Spell&userspell=$(sp hurt)&round=2"; done
for seed in 5 6 7; do fa_both sleep "$seed" fa_slime "spell=Spell&userspell=$(sp sleep)&round=2"; done
fa_expect 'any(s["key"] == "sleep" and s["who"] == "enemy" and s["change"] == "add" for e in d["events"] for s in e.get("status", []))' "Sleep: a status"
fa_herb() { fa_hurt; t_give fapi herb 2; }
for seed in 1 2; do fa_both herb "$seed" fa_herb "item=Use+Item&useritem=$(it herb)&round=2"; done
fa_expect 'any(e["type"] == "item" and e["text"] == "You have used the Herb, and gained 30 Hit Points." and e["hp"] == [{"who": "player", "id": 1, "name": "Fapi", "from": 150, "to": 180, "max": 300}] for e in d["events"])' "Herb"

t_section "fight api: spell buttons, form and fetch alike"
# A spell's icon button is <button name="spell" value="<id>">; fight.js sends the form's
# fields plus the pressed button's name and value (FormData leaves buttons out), as a
# native submit does: spell=<id>. The same round both ways, and the same as the old
# select's spell=Spell&userspell=<id>.
FA_HEAL=$(sp heal)
fa_both "heal button" 1 fa_hurt "spell=$FA_HEAL&round=2"
fa_expect 'any(e["type"] == "spell" and e["text"].startswith("You have cast the Heal spell") and e["mp"][0]["from"] - e["mp"][0]["to"] == 5 for e in d["events"] if "mp" in e)' "Heal button: cast"
fa_expect "'<button class=\"spell-btn\" type=\"submit\" name=\"spell\" value=\"$FA_HEAL\" title=\"Heal (5 MP)\" aria-label=\"Heal (5 MP)\"><img src=\"/static/images/skills/heal.png\"' in d['fragments']['main']" "the fragment's spell buttons"
fa_expect "'action=\"/spell/$FA_HEAL\"' in d['fragments']['nav_right'] and 'class=\"spell-btn\"' in d['fragments']['nav_right']" "the fragment's Fast Spells"
for seed in 1 2; do
	fa_both "heal button" "$seed" fa_hurt "spell=$FA_HEAL&round=2"
	FA_BUTTON=$(fa_state)
	fa_hurt; t_post /fight "csrf=$FA_CS&spell=Spell&userspell=$FA_HEAL&round=2" -H "X-Test-Seed: $seed"
	[ "$(fa_state)" = "$FA_BUTTON" ] && t_ok || t_fail "the button and the old select differ (seed $seed)"
done
for seed in 3 4; do fa_both "hurt button" "$seed" fa_slime "spell=$(sp hurt)&round=2"; done
fa_expect 'any(e["type"] == "spell" and e["text"].startswith("You have cast the Hurt spell") for e in d["events"] if "text" in e)' "Hurt button: cast"
# the MP left after the round: the buttons it no longer covers come back disabled
fa_low() { fa_slime; fa_sql "UPDATE users SET currentmp = 7"; }
fa_both "last MP" 5 fa_low "spell=$(sp hurt)&round=2"
fa_expect "'value=\"$FA_HEAL\" title=\"Heal (5 MP)\" aria-label=\"Heal (5 MP)\" disabled>' in d['fragments']['main']" "disabled after the round"

t_section "fight api: statuses, summons, locked turns"
fa_titan() { fa_player; fa_sql "UPDATE users SET dexterity = 22500"; t_fight fapi 149 30000; }
fa_both poison 1 fa_titan "spell=Spell&userspell=$(sp poison)&round=2"
fa_expect 'any(e["type"] == "spell" and e["status"][0]["key"] == "poison" and e["status"][0]["who"] == "enemy" and e["status"][0]["turns"] == 3 and e["status"][0]["status"] == "Poisoned" for e in d["events"] if "status" in e)' "Poison: the status"
fa_expect 'any(e["type"] == "status" and e["part"] == "ending" and e["actor"] == "enemy" and e["text"].startswith("The Titan takes ") and e["hp"][0]["who"] == "enemy" for e in d["events"] if "text" in e and "hp" in e)' "Poison: the tick"
fa_poisoned() { fa_titan; t_fight_status fapi 2 poison 'max=i:5
min=i:2' 1; }
fa_both "poison runs out" 2 fa_poisoned "fight=Fight&round=2"
fa_expect 'any(e["actor"] == "enemy" and e["type"] == "status" and s["change"] == "expire" and s["key"] == "poison" and s["statuses"] == [] for e in d["events"] for s in e.get("status", []))' "Poison: expiry"
fa_both regen 3 fa_titan "spell=Spell&userspell=$(sp regen)&round=2"
fa_both wolf 4 fa_titan "spell=Spell&userspell=$(sp call_wolf)&round=2"
fa_expect 'any(e["type"] == "spell" and e["summon"][0]["change"] == "join" and e["summon"][0]["name"] == "Wolf" and e["summon"][0]["hp"] == 30 for e in d["events"] if "summon" in e)' "Call Wolf: joins"
fa_expect 'any(e["actor"] == "ally" and e["type"] == "summon" and e["part"] == "allies" and e["text"].startswith("Your Wolf bites the monster for") for e in d["events"] if "text" in e)' "the wolf bites"
fa_both "hyper beam" 5 fa_titan "spell=Spell&userspell=$(sp hyper_beam)&round=2"
fa_expect '"name=\"continue\"" in d["fragments"]["main"] and any(s["key"] == "recharging" and s["who"] == "player" for e in d["events"] for s in e.get("status", []))'
fa_recharging() { fa_titan; t_fight_status fapi 1 recharging '' 1; }
for cmd in "continue=Continue" "fight=Fight" "spell=Spell&userspell=$(sp heal)"; do
	fa_both recharge 6 fa_recharging "$cmd&round=2"
	fa_expect 'any(e["type"] == "blocked" and e["actor"] == "player" and e["text"] == "You must recharge this turn." for e in d["events"])'
done
fa_both "continue, not locked" 7 fa_titan "continue=Continue&round=2"
fa_expect 'd["events"] == [] and d["round"] == 3'

t_section "fight api: refusals"
fa_check_refusal() {  # fa_check_refusal SETUP 'fields' 'message': nothing changes, the same text both ways
	local before st1
	$1; before=$(fa_state)
	t_post /fight "csrf=$FA_CS&$2"; expect_status 200
	[ "$(fa_py html-has "$3")" = yes ] && t_ok || t_fail "page lacks: $3"
	st1=$(fa_state); [ "$st1" = "$before" ] && t_ok || t_fail "a refusal changed: $before -> $st1"
	$1
	t_fetch /fight "$2"; expect_status 200; fa_check
	[ "$(fa_get 'd["error"]')" = "$3" ] && t_ok || t_fail "error: $(fa_get 'd.get("error")')"
	[ "$(fa_state)" = "$before" ] && t_ok || t_fail "a refusal changed (fetch)"
}
fa_full() { fa_player; t_fight fapi 2 50; t_give fapi herb 1; }
fa_check_refusal fa_full "spell=Spell&userspell=$(sp heal)&round=2" "Your Hit Points are already full. Please go back and try again."
fa_check_refusal fa_full "item=Use+Item&useritem=$(it herb)&round=2" "Your Hit Points are already full. Please go back and try again."
fa_check_refusal fa_full "spell=Spell&userspell=0&round=2" "You must select a spell first. Please go back and try again."
fa_check_refusal fa_full "item=Use+Item&useritem=$(it potion)&round=2" "You do not have this item. Please go back and try again."
fa_check_refusal fa_full "spell=Spell&userspell=$(sp fury)&round=2" "You have not yet learned this spell. Please go back and try again."
# the same refusals for a spell button's value (a direct POST: the page disables what MP don't cover)
fa_check_refusal fa_full "spell=$(sp heal)&round=2" "Your Hit Points are already full. Please go back and try again."
fa_check_refusal fa_full "spell=0&round=2" "You must select a spell first. Please go back and try again."
fa_check_refusal fa_full "spell=$(sp fury)&round=2" "You have not yet learned this spell. Please go back and try again."
fa_short() { fa_full; fa_sql "UPDATE users SET currentmp = 2"; }
fa_check_refusal fa_short "spell=$(sp hurt)&round=2" "You do not have enough Magic Points to cast this spell. Please go back and try again."

t_section "fight api: monster spells and items"
# fa_find LABEL SETUP 'fields' 'python condition on d' : the first seed (of 40) whose fetch
# answer has it, played both ways (the monsters choose by weight, so a seed decides)
fa_find() {
	local seed found=
	for seed in $(seq 1 40); do
		$2; t_fetch /fight "$3" -H "X-Test-Seed: $seed"
		if [ "$(fa_get "$4")" = true ]; then found=$seed; break; fi
	done
	if [ -z "$found" ]; then t_fail "$1: no seed of 40 gives it"; return; fi
	fa_both "$1" "$found" "$2" "$3"
	fa_expect "$4" "$1"
}
SHAMAN=$(mon goblin_shaman); WITCH=$(mon bog_witch); BANDIT=$(mon bandit_captain)
fa_monster_set() { t_sql "UPDATE fight_combatants SET $1 WHERE id = 2 AND user_id = (SELECT id FROM users $FAQ)"; }
fa_shaman_low() { fa_player; fa_sql "UPDATE users SET dexterity = 22500"; t_fight fapi "$SHAMAN" 10; fa_monster_set "mp = 0, maxmp = 17"; }
fa_find "shaman: potion" fa_shaman_low "fight=Fight&round=2" \
	'any(e["actor"] == "enemy" and e["type"] == "item" and e["text"] == "The Goblin Shaman uses the Potion." for e in d["events"] if "text" in e) and any(e["actor"] == "enemy" and e["hp"][0]["who"] == "enemy" and e["hp"][0]["to"] == 40 for e in d["events"] if "hp" in e)'
fa_shaman() { fa_player; fa_sql "UPDATE users SET dexterity = 22500"; t_fight fapi "$SHAMAN" 40; }
fa_find "shaman: Hurt" fa_shaman "fight=Fight&round=2" \
	'any(e["actor"] == "enemy" and e["type"] == "spell" and e["text"].startswith("The monster casts Hurt on you for") and e["hp"][0]["who"] == "player" and e["mp"][0]["who"] == "enemy" and e["mp"][0]["from"] == 17 for e in d["events"] if "hp" in e and "mp" in e)'
fa_witch() { fa_player; fa_sql "UPDATE users SET dexterity = 22500"; t_fight fapi "$WITCH" 60; }
fa_find "witch: Sleep" fa_witch "fight=Fight&round=2" \
	'any(e["actor"] == "enemy" and e["type"] == "spell" and s["who"] == "player" and s["key"] == "sleep" for e in d["events"] for s in e.get("status", []))'
fa_expect 'not any("mp" in e for e in d["events"] if e.get("actor") == "enemy")' "free spells: no MP change"
fa_bandit() { fa_player; fa_sql "UPDATE users SET dexterity = 22500"; t_fight fapi "$BANDIT" 145; fa_monster_set "maxhp = 145"; }
fa_find "bandit: Craze" fa_bandit "fight=Fight&round=2" \
	'any(e["actor"] == "enemy" and e["type"] == "spell" and s["who"] == "enemy" and s["key"] == "uber_damage" for e in d["events"] for s in e.get("status", []))'
fa_expect '"Damage Up" in d["fragments"]["main"]'
# an attack-only monster: its MP isn't on the page
fa_slime; t_fetch /fight "fight=Fight&round=2"; fa_check
fa_expect '"fight-monstermp" not in d["fragments"]["main"] and "fight-monsterhp" in d["fragments"]["main"]'

t_section "fight api: death"
fa_doomed() { fa_player; fa_sql "UPDATE users SET currenthp = 1, dexterity = 0"; t_fight fapi 151 30000; }
fa_both death 1 fa_doomed "fight=Fight&round=2"
fa_expect 'd["events"][-1]["type"] == "death" and "<b>You have died.</b>" in d["fragments"]["main"] and "round" not in d'
fa_expect '"name=\"fight\"" not in d["fragments"]["main"] and d["url"] == "/fight"'
fa_is currentaction "In Town"
t_get /dead -H 'Accept: application/json'; expect_status 200; fa_check
fa_expect '"You have died." in d["fragments"]["main"] and d["title"] == "You Have Died" and d["url"] == "/dead"'

t_section "fight api: stale rounds"
fa_player; t_fight fapi 2 500
t_post /fight "csrf=$FA_CS&fight=Fight&round=1"; expect_status 200
expect_body 'That command came from an older page, so nothing happened.'
expect_no_body 'class="fight-yourturn"'; expect_body 'name="round" value="3"'
fa_is "$T_MONSTER_HP" 500; fa_is "$T_ROUND" 3
# a second click: the first plays, the second is stale
t_post /fight "csrf=$FA_CS&fight=Fight&round=3"; expect_body 'You attack the monster for'; expect_no_body 'fight-stale'
HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $FAQ"); fa_is "$T_ROUND" 4
t_post /fight "csrf=$FA_CS&fight=Fight&round=3"; expect_body 'fight-stale'; expect_no_body 'You attack the monster for'
fa_is "$T_MONSTER_HP" "$HP"; fa_is "$T_ROUND" 5
# the same with fetch
t_fetch /fight "fight=Fight&round=5"; fa_check; fa_expect '"stale" not in d and len(d["events"]) > 0 and d["round"] == 6'
HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $FAQ")
t_fetch /fight "fight=Fight&round=5"; expect_status 200; fa_check
fa_expect 'd["stale"] is True and d["events"] == [] and d["round"] == 7 and "fight-stale" in d["fragments"]["main"]'
fa_is "$T_MONSTER_HP" "$HP"
t_fetch /fight "fight=Fight&round=x"; fa_check; fa_expect 'd["stale"] is True'
# long fights: the counter goes past the original's cap of 255, stale rounds are still caught
fa_player; t_fight fapi 2 5000 255
t_post /fight "csrf=$FA_CS&fight=Fight&round=255"; expect_body 'You attack the monster for'; fa_is "$T_ROUND" 256
expect_body 'name="round" value="256"'
t_post /fight "csrf=$FA_CS&fight=Fight&round=255"; expect_body 'fight-stale'; fa_is "$T_ROUND" 257
fa_sql "UPDATE users SET currenthp = 300"
t_sql "UPDATE fights SET round = 301 WHERE user_id = (SELECT id FROM users $FAQ)"
t_post /fight "csrf=$FA_CS&fight=Fight&round=301"; expect_body 'You attack the monster for'; fa_is "$T_ROUND" 302
HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $FAQ")
t_post /fight "csrf=$FA_CS&fight=Fight&round=301"; expect_body 'fight-stale'; expect_no_body 'You attack the monster for'
fa_is "$T_MONSTER_HP" "$HP"; fa_is "$T_ROUND" 303
t_fetch /fight "fight=Fight&round=303"; fa_check; fa_expect '"stale" not in d and len(d["events"]) > 0 and d["round"] == 304'
HP=$(t_sql "SELECT $T_MONSTER_HP FROM users $FAQ")
t_fetch /fight "fight=Fight&round=303"; fa_check; fa_expect 'd["stale"] is True and d["events"] == [] and d["round"] == 305'
fa_is "$T_MONSTER_HP" "$HP"
# a won fight: on to the victory; a fight that is over: home
fa_sql "UPDATE users SET currenthp = 300"
t_sql "UPDATE fight_combatants SET hp = 0 WHERE side = 'enemy' AND user_id = (SELECT id FROM users $FAQ)"
t_fetch /fight "fight=Fight&round=1"; fa_check; fa_expect 'd["redirect"] == "/victory" and d["stale"] is True'
t_post /fight "csrf=$FA_CS&fight=Fight&round=1"; expect_redirect /victory
t_fight_clear fapi; fa_sql "UPDATE users SET currentaction = 'Exploring'"
t_post /fight "csrf=$FA_CS&fight=Fight&round=9"; expect_redirect /
t_fetch /fight "fight=Fight&round=9"; fa_check; fa_expect 'd["redirect"] == "/" and d["stale"] is True'
t_post /fight "csrf=$FA_CS&fight=Fight"; expect_body 'Cheat attempt detected.'   # no round: as before
t_fetch /fight "fight=Fight"; fa_check; fa_expect 'd["error"].startswith("Cheat attempt detected.")'

t_section "fight api: CSRF"
fa_slime; BEFORE=$(fa_state)
t_req POST /fight --data "fight=Fight&round=2" -H 'Accept: application/json'; expect_status 403
t_req POST /fight --data "fight=Fight&round=2" -H 'Accept: application/json' -H "X-CSRF-Token: $(printf '0%.0s' $(seq 64))"
expect_status 403
[ "$(fa_state)" = "$BEFORE" ] && t_ok || t_fail "a POST without the token changed the fight"
t_req POST /drop --data "take=Take+it" -H 'Accept: application/json'; expect_status 403

t_section "fight api: item drops"
t_fight_clear fapi; fa_player; fa_sql "UPDATE users SET currentaction = 'Exploring', dropcode = $(it life_pebble)"
t_get /drop -H 'Accept: application/json'; expect_status 200; fa_check
fa_expect '"<b>Life Pebble</b>" in d["fragments"]["main"] and "data-fight" in d["fragments"]["main"] and d["url"] == "/drop" and d["title"] == "Item Drop"'
t_fetch /drop "take=Take+it"; expect_status 200; fa_check
fa_expect '"The Life Pebble is in your bag." in d["fragments"]["main"] and "<b>1</b>/12</span>" in d["fragments"]["nav_right"]'
fa_is dropcode 0; fa_is "$T_ITEMS" life_pebble
t_get /drop -H 'Accept: application/json'; fa_check; fa_expect 'd["redirect"] == "/"'
fa_sql "UPDATE users SET dropcode = $(it life_pebble)"
t_fetch /drop "leave=Leave+it"; fa_check; fa_expect 'd["redirect"] == "/"'; fa_is dropcode 0
for k in stick branch club dagger hatchet axe brand poleaxe broadsword battle_axe claymore; do t_give fapi "$k"; done
fa_sql "UPDATE users SET dropcode = $(it life_pebble)"
t_fetch /drop "take=x&discard=999999"; fa_check
fa_expect 'd["error"] == "Please go back and select an item from your bag to discard."'
t_fetch /drop "take=x"; fa_check; fa_expect '"Your bag is full. Choose an item to discard first" in d["fragments"]["main"]'
fa_is dropcode "$(it life_pebble)"
t_items_clear fapi; fa_sql "UPDATE users SET dropcode = 0"

t_section "fight api: cleanup"
t_fight_clear fapi
fa_sql "UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0"
t_get /; expect_status 200

fi
