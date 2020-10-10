<?php

/**
 * This script handles all the functionality of the internal forum.
 */

require 'app/Libs/Helpers.php';

$link = openLink();
$control = getControl($link);

// See if the game is closed; die if it is.
dieIfGameClosed($control);

// See if the user is logged in. If not, redirect. If so, get their data.
$user = getUserIfLoggedInByCookie($link);

// Perform usual authentication checks.
redirectIfNotVerified($user['verify'], $control['verifyemail']);
dieIfBanned($user['authlevel']);

// Get the requested action, or default to the user's current action.
$do = GET('do', 'default');

// If the game is closed, set our action to the correct endpoint.
if ($control['gameopen'] == 0) { $do = 'gameClosed'; }

if ($do == "thread") { showThread($link); }
elseif ($do == "new") { newThread($user, $link); }
elseif ($do == "reply") { reply($user, $link); }
else { showThreads($link); }

function showThreads($link)
{
    $page = gettemplate('forum/main');

    $query = query("select * from {{ table }} where parent='0' order by newpostdate desc limit 20", 'forum', $link);
    $threads = $query->fetchAll();
    $list = '';

    if (! $threads || count($threads) === 0) {
        $page = gettemplate('forum/noThreads');
    } else {
        foreach ($threads as $row) {
            $row['title'] = safe($row['title']);
            $row['date'] = prettydate($row['newpostdate']);

            $thread = gettemplate('forum/threadRow');

            $list .= parsetemplate($thread, $row);
        }
    }

    $page = parsetemplate($page, ['list' => $list]);
    
    display($page, 'Forum');
}

function showThread($link)
{
    $id = GET('id', function() { redirect('forum.php'); });
    $start = GET('start', 0);

    $query = prepare("select * from {{ table }} where id=? or parent=? order by id limit {$start},15", 'forum', $link);
    $query2 = prepare('select title from {{ table }} where id=? limit 1', 'forum', $link);
    $row2 = execute($query2, [$id])->fetch();
    $rows = execute($query, [$id, $id]);

    $page = gettemplate('forum/thread');
    $data['title'] = safe($row2["title"]);
    $data['list'] = '';
    $data['id'] = $id;

    foreach ($rows->fetchAll() as $row) {
        $author = safe($row['author']);
        $content = nl2br(safe($row['content']));
        $date = prettydate($row['postdate']);

        $data['list'] .= <<<ROW
        <div class="mb-8">
            <div class="px-4 py-4 flex justify-between items-center mb-2" style="font-size: 1.25rem; background-color: #dbdbdb;">
                <span class="title">{$author}</span> <span style="font-size: 1rem;">{$date}</span>
            </div>
            <div>
               {$content}
            </div>
        </div>
ROW;
    }

    $page = parsetemplate($page, $data);
    display($page, "{$data['title']} - Forum");
}

function reply($user, $link)
{
    $data = trimData($_POST);

    $query = prepare('insert into {{ table }} set postdate=now(), newpostdate=now(), author=?, parent=?, title=?, content=?', 'forum', $link);
    $query2 = prepare('update {{ table }} set newpostdate=now(), replies = replies + 1 where id=?', 'forum', $link);

    execute($query, [$user['username'], $data['parent'], $data['title'], $data['content']]);
    execute($query2, [$data['parent']]);
    
	redirect("forum.php?do=thread&id={$data['parent']}");
}

function newThread($user, $link)
{
    if (isset($_POST["submit"])) {
        $data = trimData($_POST);
        $query = prepare("insert into {{ table }} set postdate=now(), newpostdate=now(), author=?, parent='0', title=?, content=?", 'forum', $link);

        execute($query, [$user['username'], $data['title'], $data['content']]);

        redirect('forum.php');
    }
    
    $page = gettemplate('forum/new');
    display($page, "Forum");
}