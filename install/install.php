<?php

/**
 * This script handles initial setup for the game. It creates the database tables,
 * fills them with basic content if desired, and creates an admin account for the
 * user.
 */

// The core game file contains all the stuff we need to make the installer work.
require '../app/Game.php';

$request = GET('step', 'intro');

// Decipher which page we want to go to.
if ($request == 'database') { database(); }
elseif ($request == 'admin') { admin(); }
elseif ($request == 'finish') { finish(); }
else { intro(); }

function getQuery(string $query)
{
    return file_get_contents("sql/{$query}.sql");
}

function doInstallQuery(string $query, string $table, string $verb = 'create', array $extras = [])
{
    global $link;

    $query = getQuery($query);
    if (! empty($extras)) { $query = parse($query, $extras); }
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

    // Some of the new tables (as of v2.0.0) require a foreign key for the users table. Due to this, they require
    // an extra parse to properly link it to the users table.
    $results[] = doInstallQuery('createInventories', 'inventories', 'create', ['users' => prefix('users')]);
    $results[] = doInstallQuery('createFights', 'fights', 'create', ['users' => prefix('users')]);
    $results[] = doInstallQuery('createInventories', 'inventories', 'create', ['users' => prefix('users')]);

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
    foreach ($results as $r) {
        $result .= "<li>{$r}</li>";
    }
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

        return admin($list);
    }

    createUser([
        'username' => $data['username'],
        'password' => password_hash($data['password1'], PASSWORD_DEFAULT),
        'email' => $data['email'],
        'verified' => 1,
        'class' => $data['class'],
        'difficulty' => $data['difficulty'],
        'role' => 'admin'
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