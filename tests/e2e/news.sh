# tests/e2e/news.sh :: news posts (title, author, discussion thread in the News board), the
# town news box, the /news archive and the News board rules. Sourced by tests/run.sh.
# Everything it adds is removed at the end and the control settings restored.

news_eq() {  # news_eq "SQL" expected label
	local got
	got=$(t_sql "$1")
	if [ "$got" = "$2" ]; then t_ok; else t_fail "$3: expected '$2', got '$got'"; fi
}
news_count() {  # occurrences of a fixed string in the last body
	grep -oF -- "$1" "$BODY" | wc -l | tr -d ' '
}

if ! t_has_sql; then
	t_section "news (skipped: needs sqlite3 or python3)"
else

NEWS_MAX=$(t_sql "SELECT coalesce(max(id), 0) FROM news")
NEWS_FORUM_MAX=$(t_sql "SELECT coalesce(max(id), 0) FROM forum")
t_sql "CREATE TABLE news_snap_control AS SELECT shownews, forumtype, forumaddress FROM control"
t_sql "UPDATE control SET shownews = 1, forumtype = 1"
NEWS_ADMIN_ID=$(t_sql "SELECT id FROM users WHERE username = '$ADMIN_USER'")

t_section "news: the installed post"
news_eq "SELECT title || '|' || author_id FROM news WHERE id = 1" \
	"This is the first news post. Please use the admin control pa...|$NEWS_ADMIN_ID" "seeded post"
news_eq "SELECT f.board || '|' || f.parent || '|' || f.author || '|' || f.author_id || '|' || (f.title = n.title) || '|' || (f.content = n.content) || '|' || (f.postdate = n.postdate) FROM news n JOIN forum f ON f.id = n.thread_id WHERE n.id = 1" \
	"2|0|Admin|$NEWS_ADMIN_ID|1|1|1" "seeded post thread"

t_section "news: logged out"
t_jar newsanon; t_reset_jar
t_get /news;    expect_redirect /login
t_get /news/1;  expect_redirect /login

t_section "news: admin posts a single paragraph, no title"
t_jar newsadmin; t_login "$ADMIN_USER" "$ADMIN_PASS"
t_get /admin/news; ATOKEN=$(t_csrf)
t_post /admin/news "title=x&content=y"; expect_status 403
news_eq "SELECT count(*) FROM news WHERE id > $NEWS_MAX" "0" "no post without csrf"
t_post /admin/news "csrf=$ATOKEN&title=++&content=$(t_enc $'  Single paragraph headline that is definitely longer than sixty characters in total\r\nsecond line\r\n \r\n')"
expect_redirect '/admin/news\?saved=1'
N1=$(t_sql "SELECT max(id) FROM news")
T1=$(t_sql "SELECT thread_id FROM news WHERE id = $N1")
news_eq "SELECT title || '|' || author_id || '|' || (abs(postdate - strftime('%s','now')) < 60) FROM news WHERE id = $N1" \
	"Single paragraph headline that is definitely longer than six...|$NEWS_ADMIN_ID|1" "default title"
news_eq "SELECT f.board || '|' || f.parent || '|' || f.replies || '|' || f.author || '|' || f.author_id || '|' || (f.title = n.title) || '|' || (f.content = n.content) || '|' || (f.postdate = n.postdate) || '|' || (f.newpostdate = n.postdate) FROM news n JOIN forum f ON f.id = n.thread_id WHERE n.id = $N1" \
	"2|0|0|Admin|$NEWS_ADMIN_ID|1|1|1|1" "thread in the News board"

t_section "news: town box, single paragraph"
t_jar newsplayer; t_reset_jar
t_register newsy newspw1 newsy@example.com Newsy; t_login newsy newspw1
NEWSY_ID=$(t_sql "SELECT id FROM users WHERE username = 'newsy'")
t_get /;        expect_body 'Latest News'
expect_body "<article class=\"news-post\">
<h2 class=\"news-title\"><a href=\"/news/$N1\">Single paragraph headline that is definitely longer than six...</a></h2>"
expect_body '&middot; by Admin</p>'; expect_body 'second line'; expect_no_body '>Read more</a>'
expect_body "<a href=\"/forum/thread/$T1\">Reply</a> &middot; <a href=\"/news\">All news</a>"
expect_body '<a href="/news">News</a><br>'

t_section "news: admin posts several paragraphs with a title"
t_jar newsadmin
t_post /admin/news "csrf=$ATOKEN&title=$(t_enc '<script>t()</script> Patch & notes')&content=$(t_enc $'First <b>para</b>\r\nstill first\r\n \t \r\nSecond <i>para</i>\r\n\r\nThird')"
expect_redirect '/admin/news\?saved=1'
N2=$(t_sql "SELECT max(id) FROM news")
T2=$(t_sql "SELECT thread_id FROM news WHERE id = $N2")
news_eq "SELECT title || '|' || author_id FROM news WHERE id = $N2" "<script>t()</script> Patch & notes|$NEWS_ADMIN_ID" "titled post"
news_eq "SELECT board || '|' || title FROM forum WHERE id = $T2" "2|<script>t()</script> Patch & notes" "titled thread"

t_section "news: town box, first paragraph + Read more"
t_jar newsplayer
t_get /
expect_body "<h2 class=\"news-title\"><a href=\"/news/$N2\">&lt;script&gt;t()&lt;/script&gt; Patch &amp; notes</a></h2>"; expect_no_body '<script>t()'
expect_body 'First &lt;b&gt;para&lt;/b&gt;<br />'; expect_body 'still first'
expect_no_body 'Second &lt;i&gt;para'; expect_no_body 'Third'
expect_body "still first <a href=\"/news/$N2\">Read more</a>"
expect_body "<a href=\"/forum/thread/$T2\">Reply</a>"

t_section "news: replies and their count"
t_get "/forum/thread/$T2"; PTOKEN=$(t_csrf)
expect_body "<a href=\"/forum\">Forum</a> &rsaquo; <a href=\"/forum/2\">News</a></span></nav>"; expect_body '<h1 class="forum-title">&lt;script&gt;t()'
expect_body 'Second &lt;i&gt;para&lt;/i&gt;'; expect_body "action=\"/forum/reply/$T2\""
t_post "/forum/reply/$T2" "content=nope"; expect_status 403
t_post "/forum/reply/$T2" "csrf=$PTOKEN&content=$(t_enc 'First!')"; expect_redirect "/forum/thread/$T2"
news_eq "SELECT board || '|' || author || '|' || author_id FROM forum WHERE parent = $T2" "2|Newsy|$NEWSY_ID" "reply row"
t_get /;        expect_body "<a href=\"/forum/thread/$T2\">1 reply</a>"
t_jar newsadmin
t_get "/forum/thread/$T2"
t_post "/forum/reply/$T2" "csrf=$(t_csrf)&content=Thanks"; expect_redirect "/forum/thread/$T2"
t_jar newsplayer
t_get /;        expect_body "<a href=\"/forum/thread/$T2\">2 replies</a>"
t_get "/news/$N2"; expect_body "<a href=\"/forum/thread/$T2\">2 replies</a>"

t_section "news: one post"
t_get "/news/$N2"; expect_status 200
expect_body '<title>&lt;script&gt;t()&lt;/script&gt; Patch &amp; notes</title>'
expect_body "<a href=\"/news/$N2\">&lt;script&gt;t()&lt;/script&gt; Patch &amp; notes</a>"
expect_body 'Second &lt;i&gt;para&lt;/i&gt;'; expect_body 'Third'; expect_no_body '<i>para'
expect_body '&middot; by Admin</p>'; expect_body '<a href="/news">All news</a>'; expect_no_body 'Read more'
t_get /news/999999; expect_status 404; expect_body 'That news post doesn&#39;t exist.'
t_get /news/abc;    expect_status 404
t_sql "UPDATE news SET author_id = 999999 WHERE id = $N1"
t_get "/news/$N1"; expect_body '&middot; by Unknown</p>'
t_sql "UPDATE news SET author_id = $NEWS_ADMIN_ID WHERE id = $N1"

t_section "news: the News board"
t_get /forum;   expect_body 'href="/forum/2"><b>News</b></a><br><span class="small">Game news and announcements. Reply to discuss.</span></td>'
NB_THREADS=$(t_sql "SELECT count(*) FROM forum WHERE board = 2 AND parent = 0")
NB_POSTS=$(t_sql "SELECT count(*) FROM forum WHERE board = 2")
expect_body "Reply to discuss.</span></td><td>$NB_THREADS</td><td>$NB_POSTS</td>"
t_get /forum/2; expect_status 200; expect_body "href=\"/forum/thread/$T2\">&lt;script&gt;"
expect_no_body 'New Thread'; expect_no_body 'href="/forum/2/new"'
t_get /forum/2/new; expect_status 403; expect_body 'Only administrators can start threads in News.'
t_post /forum/2/new "csrf=$PTOKEN&title=Fake+news&content=x"; expect_status 403
news_eq "SELECT count(*) FROM forum WHERE title = 'Fake news'" "0" "player thread in News"
t_post /forum/2/new "title=x&content=x"; expect_status 403
t_get /forum/1; expect_body 'href="/forum/1/new"'
t_jar newsadmin
t_get /forum/2; expect_body 'href="/forum/2/new"'
t_get /forum/2/new; expect_status 200; expect_body 'action="/forum/2/new"'
t_post /forum/2/new "title=NoToken&content=x"; expect_status 403
t_post /forum/2/new "csrf=$(t_csrf)&title=Admin+thread&content=Board+only"; expect_redirect /forum/2
news_eq "SELECT board || '|' || author_id FROM forum WHERE title = 'Admin thread'" "2|$NEWS_ADMIN_ID" "admin thread"
news_eq "SELECT count(*) FROM news WHERE content = 'Board only'" "0" "a board thread is not news"
# an empty board, and escaping of board names
t_sql "INSERT INTO forums (id, name, description, position) VALUES (99, '<b>Empty</b>', '<i>d</i>', 9)"
t_get /forum;   expect_body 'href="/forum/99"><b>&lt;b&gt;Empty&lt;/b&gt;</b></a><br><span class="small">&lt;i&gt;d&lt;/i&gt;</span></td><td>0</td><td>0</td><td>None</td>'
t_get /forum/99; expect_body 'No threads in this board.'; expect_body '&rsaquo; &lt;b&gt;Empty&lt;/b&gt;'
t_sql "DELETE FROM forums WHERE id = 99"

t_section "news: archive paging"
t_sql "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM c WHERE n < 12)
			 INSERT INTO news (postdate, title, content, author_id) SELECT 1000 + n, 'Bulk news ' || n, 'bulk ' || n || '.', $NEWS_ADMIN_ID FROM c"
NEWS_TOTAL=$(t_sql "SELECT count(*) FROM news")
t_jar newsplayer
t_get /news;    expect_status 200; expect_body '<h1 class="title page-title news-heading">News</h1>'
[ "$(news_count 'class="news-post"')" = 10 ] && t_ok || t_fail "10 posts on the first page"
expect_body '>Bulk news 12</a>'; expect_body '>Bulk news 3</a>'; expect_no_body '>Bulk news 2</a>'
expect_body '<span class="forum-page-current" aria-current="page">1</span>'; expect_body 'href="/news?start=10"'
# bulk posts have no thread: no link for them
[ "$(news_count 'href="/forum/thread/')" = 0 ] && t_ok || t_fail "thread links for posts without threads"
t_get "/news?start=10"
[ "$(news_count 'class="news-post"')" = $((NEWS_TOTAL - 10 < 10 ? NEWS_TOTAL - 10 : 10)) ] && t_ok || t_fail "second page size"
expect_body '>Bulk news 2</a>'; expect_body '<span class="forum-page-current" aria-current="page">2</span>'; expect_body 'href="/news">1</a>'
t_get "/news?start=abc"; expect_status 200; expect_body '<span class="forum-page-current" aria-current="page">1</span>'
t_sql "DELETE FROM news WHERE title LIKE 'Bulk news %'"
t_get /news
expect_body "<a href=\"/news/$N2\">&lt;script&gt;t()&lt;/script&gt; Patch &amp; notes</a>"
expect_body 'Second &lt;i&gt;para&lt;/i&gt;'; expect_no_body '<script>t()'
expect_body "<a href=\"/forum/thread/$T1\">Reply</a>"; expect_body "<a href=\"/forum/thread/$T2\">2 replies</a>"

t_section "news: without the built-in forum"
t_sql "UPDATE control SET forumtype = 0"
t_get /;        expect_body 'Latest News'; expect_body 'still first'; expect_body '<a href="/news">All news</a>'
expect_no_body 'href="/forum/thread/'; expect_body '<a href="/news">News</a>'
t_get /news;    expect_status 200; expect_no_body 'href="/forum/thread/'
t_get "/news/$N2"; expect_status 200; expect_no_body 'href="/forum/thread/'
# admins can still post: the thread is created for when the forum is turned on
t_jar newsadmin
t_post /admin/news "csrf=$ATOKEN&title=Offline&content=While+the+forum+is+off"
news_eq "SELECT f.board || '|' || f.title FROM news n JOIN forum f ON f.id = n.thread_id WHERE n.title = 'Offline'" "2|Offline" "thread while the forum is off"
t_sql "UPDATE control SET forumtype = 2, forumaddress = 'https://forum.example.com/'"
t_jar newsplayer
t_get /;        expect_body 'While the forum is off'; expect_no_body 'href="/forum/thread/'
t_sql "UPDATE control SET forumtype = 1, forumaddress = ''"
t_get /;        expect_body '>Reply</a> &middot; <a href="/news">All news</a>'

t_section "news: town box off"
t_sql "UPDATE control SET shownews = 0"
t_get /;        expect_no_body 'Latest News'; expect_body '<a href="/news">News</a>'
t_get /news;    expect_status 200

# restore
t_sql "DELETE FROM news WHERE id > $NEWS_MAX; DELETE FROM forum WHERE id > $NEWS_FORUM_MAX;
			 UPDATE control SET (shownews, forumtype, forumaddress) =
				 (SELECT shownews, forumtype, forumaddress FROM news_snap_control);
			 DROP TABLE news_snap_control;"
t_jar default

fi
