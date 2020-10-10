<?php

/**
 * This script handles initial setup for the game. It creates the database tables,
 * fills them with basic content if desired, and creates an admin account for the
 * user.
 */

 // Get our libraries...
require '../app/Libs/Helpers.php';
require '../app/Libs/Validation.php';

// Open a link to the DB and get our page request.
$link = openLink();
$request = GET('step', 'intro');

// Decipher which page we want to go to.
if ($request == 'database') { database(); }
elseif ($request == 'admin') { admin(); }
elseif ($request == 'finish') { finish(); }
else { intro(); }

/**
 * Get a query file and it's contents from our sql/ directory.
 */
function getQuery(string $query)
{
    return file_get_contents("sql/{$query}.sql");
}

/**
 * Performs an install query. Just a convenient wrapper. Also
 * returns a result string.
 */
function doInstallQuery(string $query, string $table, string $verb = 'create')
{
    global $link;

    $query = getQuery($query);
    $result = query($query, $table, $link);

    if ($verb === 'create') {
        return $result ? "Created {$table} table." : "Failed to create {$table}.";
    } elseif ($verb === 'populate') {
        return $result ? "Populated {$table} table." : "Failed to populate {$table}.";
    } else {
        return $result ? 'Performed an install query.' : 'An install query failed.';
    }
}

/**
 * Introduction page. Explains a bit of history of the game, and gives a little advice for
 * the install.
 */
function intro()
{
    echo buildInstall(view('install/intro'), 'Intro');
}

/**
 * This bulky function is what loops through our tables and gets them created, and populated
 * with basic content if desired.
 */
function database()
{
    global $link;

    $results = [];

    // These are the table we can loop through easily and create, so we will!
    $tables = ['Control', 'Drops', 'Items', 'Forum', 'Levels', 'Monsters', 'News', 'Spells', 'Towns', 'Users'];
    foreach ($tables as $table) {
        $results[] = doInstallQuery("create{$table}", strtolower($table));
    }

    // Because the inventories have a foreign key linking them to a user, we need to parse it serparately to provide a
    // prefixed users table, if necessary.
    $query = getQuery('createInventories');
    $query = parse($query, ['users' => prefix('users')]);
    $results[] = query($query, 'inventories', $link) ? 'Created '.prefix('inventories').' table.' : 'Failed to create '.prefix('inventories').'.';

    // See above; it is the same case with the fights table.
    $query = getQuery('createFights');
    $query = parse($query, ['users' => prefix('users')]);
    $results[] = query($query, 'fights', $link) ? 'Created '.prefix('fights').' table.' : 'Failed to create '.prefix('fights').'.';

    // See above; the new Babble system requires messages be linked to the user who submitted them.
    $query = getQuery('createBabble');
    $query = parse($query, ['users' => prefix('users')]);
    $results[] = query($query, 'babble', $link) ? 'Created '.prefix('babble').' table.' : 'Failed to create '.prefix('babble').'.';

    // Since the game needs basic settings no matter what, we'll populate the control table with a default row here.
    $query = "insert into {{ table }} (id) values (null);";
    $results[] = query($query, 'control', $link) ? 'Populated '.prefix('control').' table.' : 'Failed to populate '.prefix('control').'.';

    // We'll populate the tables with some basic content if the "Complete" install was selected.
    if (isset($_POST['complete'])) {
        $tables = ['Drops', 'Items', 'Levels', 'Monsters', 'Spells', 'Towns'];
        foreach ($tables as $table) {
            $results[] = doInstallQuery("pop{$table}", strtolower($table), 'populate');
        }
    }

    $result = '';
    foreach ($results as $r) { $result .= "<li>{$r}</li>"; }
    $result = "<ul>{$result}</ul>";

    $page = view('install/database', ['result' => $result]);
    echo buildInstall($page, 'Database');
}

// The admin account form page!
function admin(string $errors = '')
{
    $page = view('install/admin', ['errors' => $errors]);
    echo buildInstall($page, 'Administrator');
}

// If all checks out, create the adming account and congratulate the player.
function finish()
{
    global $link;

    $data = trimData($_POST);
    $errors = [];

    required($data['username']) ?: $errors[] = 'Username is required.';
    required($data['password1']) ?: $errors[] = 'Password is required.';
    required($data['password2']) ?: $errors[] = 'Password confirmation is required.';
    matches($data['password1'], $data['password2']) ?: $errors[] = 'Passwords must match.';
    required($data['email']) ?: $errors[] = 'Email is required.';
    is_email($data['email']) ?: $errors[] = 'Must give valid email address.';

    if (! empty($errors)) {
        $list = '';
        foreach ($errors as $error) { $list .= "<li>{$error}</li>"; }
        $list = "<ul>{$list}</ul>";

        admin($list);
        return;
    }

    $password = password_hash($data['password1'], PASSWORD_DEFAULT);
    
    $query = "insert into {{ table }} set username=?, password=?, email=?, verified='1', class=?, registered=now(), online_last=now(), role='admin';";
    quick($query, 'users', [
        $data['username'],
        $password,
        $data['email'],
        $data['class'],
    ], $link);

    // If all is well, we'll create a file in the app/ directory that will
    // be used to tell the game we're installed!
    file_put_contents(ROOT.'/app/installed.txt', 'Installation completed on '.date('m/d/Y h:i:s a'));

    echo buildInstall(view('install/finish'), 'Finished');
}

function buildInstall($page, $title)
{
    global $start, $version, $build;

    return view('install/layout', [
        'content' => $page,
        'title' => $title,
        'time' => round(microtime(true) - $start, 4),
        'queries' => getQueries(),
        'version' => $version,
        'build' => $build
    ]);
}