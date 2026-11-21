# tests/e2e/browser.sh :: the live client in a real browser (tests/browser/client.js over
# the DevTools protocol): navigation without page loads, forms, back/forward and scroll,
# typed text kept, the progress bar, a newer link winning, another layout, a broken page
# loaded natively. Needs node (or Windows' node.exe under WSL) and Chrome, Edge or
# Chromium (BROWSER=path picks one); skipped otherwise. Sourced by tests/run.sh.
if [ -z "${NODE:-}" ]; then
	t_section "browser (skipped: no node)"
else

t_section "browser: the live client"
t_jar browser; t_reset_jar
t_register browseruser browserpw1 browser@example.com Browser 2
expect_body 'Your account was created succesfully'
t_spells browseruser 1,6   # the hotbar's page: Heal and Hurt to drag
if out=$(cat "$ROOT/tests/browser/client.js" | timeout 180 "$NODE" - "$BASE" browseruser browserpw1 2>&1); then
	case $out in
		skip:*) echo "   (browser test skipped: ${out#skip: })" ;;
		*) t_ok; echo "   browser: $out" ;;
	esac
else
	t_fail "browser test: $out"
fi
t_sql "DELETE FROM fights WHERE user_id = (SELECT id FROM users WHERE username = 'browseruser');
	UPDATE users SET currentaction = 'In Town', latitude = 0, longitude = 0 WHERE username = 'browseruser'"

fi
