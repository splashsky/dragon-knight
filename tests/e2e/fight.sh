# tests/e2e/fight.sh :: fight / victory / drop / dead. Sourced by tests/run.sh.
if t_has_sql; then

t_section "fight: setup + guards"
t_jar fighter
t_register fighter fightpw fighter@example.com Fighter 2 1   # Warrior, Easy
t_login fighter fightpw
FQ="WHERE username = 'fighter'"
f_sql() { t_sql "$1 $FQ"; }
f_col() { t_sql "SELECT $1 FROM users $FQ"; }
f_is() { # f_is COLUMN EXPECTED
  local got; got=$(f_col "$1")
  if [ "$got" = "$2" ]; then t_ok; else t_fail "users.$1: expected '$2', got '$got'"; fi
}
t_get /fight;   expect_status 200; expect_body 'Cheat attempt detected.'
t_get /victory; expect_redirect /
t_get /drop;    expect_redirect /
t_get /dead;    expect_status 200; expect_body 'You have died.'

# an encounter just began (monster not picked yet): no free victory
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currentmonster = 0, currentmonsterhp = 0"
t_get /victory; expect_redirect /
f_is currentfight 1
t_get /;        expect_redirect /fight

t_section "fight: monster selection"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, latitude = -50, longitude = 7,
  currenthp = 1000, maxhp = 1000"
t_get /fight;   expect_status 200; expect_body 'title_fighting.gif'; expect_body 'You are fighting a <b>'
expect_body "Monster's HP: "; expect_body 'name="fight"'; expect_body 'name="run"'
f_is currentfight 2
lvl=$(t_sql "SELECT m.level FROM users u JOIN monsters m ON m.id = u.currentmonster $FQ")
[ -n "$lvl" ] && [ "$lvl" -ge 9 ] && [ "$lvl" -le 11 ] && t_ok || t_fail "monster level $lvl not in 9..11"
hp=$(f_col currentmonsterhp)
[ "$hp" -gt 0 ] && t_ok || t_fail "monster hp $hp"
t_post /fight "fight=Fight"; expect_status 403          # CSRF required
f_is currentfight 2
t_get /fight; expect_body "Monster's HP: $hp"; f_is currentfight 3   # refresh: same monster

t_section "fight: run away"
CS=$(t_csrf)
t_post /fight "csrf=$CS&run=Run"; expect_redirect /
f_is currentaction Exploring
t_get /fight; expect_body 'Cheat attempt detected.'

t_section "fight: victory + level up"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, latitude = 0, longitude = 0,
  attackpower = 500, currenthp = 500, maxhp = 500, experience = 17, gold = 100"
t_get /fight; CS=$(t_csrf)
for _ in $(seq 1 30); do
  t_post /fight "csrf=$CS&fight=Fight"
  [ "$STATUS" = 302 ] && break
done
expect_redirect /victory
f_is currentmonsterhp 0
t_get /victory; expect_status 200
expect_body 'Congratulations. You have defeated the'; expect_body 'You have gained a level!'
expect_body 'You gain 2 hit points.'; expect_body 'You gain 4 magic points.'; expect_body 'You have learned a new spell.'
expect_body '<title>Courage and Wit have served thee well!</title>'
f_is level 2; f_is maxhp 502; f_is maxmp 4; f_is maxtp 11; f_is strength 7; f_is dexterity 6
f_is attackpower 502; f_is defensepower 6; f_is spells 0,1
f_is currentaction Exploring; f_is currentfight 0; f_is currentmonster 0
[ "$(f_col experience)" -ge 18 ] && t_ok || t_fail "experience not awarded"
[ "$(f_col gold)" -gt 100 ] && t_ok || t_fail "gold not awarded"
t_get /victory; expect_redirect /                     # only once

t_section "fight: victory without level up"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currentuberdamage = 10"
t_get /fight; CS=$(t_csrf)
for _ in $(seq 1 30); do
  t_post /fight "csrf=$CS&fight=Fight"
  [ "$STATUS" = 302 ] && break
done
expect_redirect /victory
t_get /victory; expect_body '<title>Victory!</title>'; expect_no_body 'gained a level'
f_is level 2; f_is currentuberdamage 0

t_section "fight: spells"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 1, currenthp = 100, currentmp = 10, maxmp = 50"
t_get /fight; CS=$(t_csrf)
expect_body '<option value="1">Heal</option>'
t_post /fight "csrf=$CS&spell=Spell&userspell=0"; expect_body 'You must select a spell first.'
t_post /fight "csrf=$CS&spell=Spell";            expect_body 'You must select a spell first.'
t_post /fight "csrf=$CS&spell=Spell&userspell=6"; expect_body 'You have not yet learned this spell.'
t_post /fight "csrf=$CS&spell=Spell&userspell=$(t_enc "1' OR '1'='1")"; expect_body 'You have not yet learned this spell.'
t_post /fight "csrf=$CS&spell=Spell&userspell=999"; expect_body 'You have not yet learned this spell.'
f_is currentmp 10
t_post /fight "csrf=$CS&spell=Spell&userspell=1"
expect_status 200; expect_body 'You have cast the Heal spell, and gained 10 Hit Points.'
f_is currentmp 5
f_sql "UPDATE users SET currentmp = 4"
t_post /fight "csrf=$CS&spell=Spell&userspell=1"; expect_body 'You do not have enough Magic Points'
f_is currentmp 4
# sleep spell, then a hurt spell that kills
f_sql "UPDATE users SET spells = '0,1,6,11', currentmp = 50, currentmonster = 2, currentmonsterhp = 50, currentmonsterimmune = 0"
t_post /fight "csrf=$CS&spell=Spell&userspell=11"
expect_body 'You have cast the Sleep spell. The monster is asleep.'
if grep -qF 'The monster is still asleep.' "$BODY"; then f_is currentmonstersleep 5
else expect_body 'The monster has woken up.'; f_is currentmonstersleep 0; fi
f_is currentmp 40
f_sql "UPDATE users SET currentmonsterhp = 1"
t_post /fight "csrf=$CS&spell=Spell&userspell=6"; expect_redirect /victory
f_is currentmonsterhp 0; f_is currentmp 35
t_get /victory; expect_body 'You have defeated the Red Slime.'

t_section "fight: death"
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 151,
  currentmonsterhp = 30000, currentmonstersleep = 0, attackpower = 1, currenthp = 1, maxhp = 30,
  dexterity = 0, defensepower = 0, gold = 101, latitude = 40, longitude = -40"
t_get /fight; CS=$(t_csrf)
t_post /fight "csrf=$CS&fight=Fight"
expect_status 200; expect_body 'The monster attacks you for'; expect_body '<b>You have died.</b>'
expect_no_body 'name="fight"'
f_is currentaction 'In Town'; f_is gold 51; f_is currenthp 8; f_is latitude 0; f_is longitude 0
f_is currentfight 0; f_is currentmonster 0
t_get /; expect_status 200; expect_body 'Town Options'

t_section "fight: item drop"
f_sql "UPDATE users SET dropcode = 1, maxhp = 30, currenthp = 30, strength = 7, attackpower = 10"
t_get /drop; expect_status 200; expect_body '<b>Life Pebble</b>'; expect_body 'Max HP +10'
expect_body 'Slot 1: None'; CS=$(t_csrf)
t_post /drop "submit=Submit&slot=1"; expect_status 403
t_post /drop "csrf=$CS&submit=Submit&slot=0"; expect_body 'Please go back and select an inventory slot'
t_post /drop "csrf=$CS&submit=Submit&slot=4"; expect_body 'Please go back and select an inventory slot'
t_post /drop "csrf=$CS&submit=Submit&slot=1"; expect_body 'The item has been equipped.'
f_is slot1id 1; f_is slot1name 'Life Pebble'; f_is maxhp 40; f_is currenthp 30; f_is dropcode 0
t_get /drop; expect_redirect /
# replace it with Demon's Sin: -10 (old) -50 (new) max HP, +50 strength and attack power
f_sql "UPDATE users SET dropcode = 13"
t_get /drop; expect_body 'Max HP-50'; expect_body 'Strength +50'; expect_body 'Slot 1: Life Pebble'
t_post /drop "csrf=$CS&submit=Submit&slot=1"; expect_body 'The item has been equipped.'
f_is slot1id 13; f_is slot1name "Demon's Sin"; f_is maxhp 0; f_is currenthp 0
f_is strength 57; f_is attackpower 60
f_sql "UPDATE users SET dropcode = 32"
t_get /drop; t_post /drop "csrf=$CS&submit=Submit&slot=3"; f_is goldbonus 10; f_is slot3name 'Fortune Drop'

t_section "fight: victory stores negative experience as 0 (MySQL UNSIGNED)"
# Blue Slime: exp rand(0,1) -> at least 1; -500% bonus: 1 + ceil(-5) = -4; gold 1
f_sql "UPDATE users SET currentaction = 'Fighting', currentfight = 2, currentmonster = 1,
  currentmonsterhp = 0, experience = 0, gold = 0, expbonus = -500, goldbonus = 0, level = 2"
t_get /victory; expect_status 200; expect_body 'You gain -4 experience.'; expect_body 'You gain 1 gold.'
f_is experience 0; f_is gold 1; f_is level 2
f_sql "UPDATE users SET expbonus = 0"

fi
