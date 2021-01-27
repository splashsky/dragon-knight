<?php

/**
 * The Game file is the glue for all the various pieces of the game that need to work together.
 * Game-wide variables are declared here, it includes all libraries and helper functions we need,
 * and establishes a focus point for all the game-wide code.
 */

// Define the directory root. Makes pathing for includes easier.
define('ROOT', $_SERVER['DOCUMENT_ROOT']);

// When set to true, DEBUG allows the game to perform functions it otherwise wouldn't be allowed to,
// such as rerunning the installer after the game has already been installed.
define('DEBUG', true);

// If we're in DEBUG mode, we'll open the floodgates of PHP's error reporting.
if (DEBUG) {
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
    error_reporting(E_ALL);
}

// We'll require the libraries that are used on every page in the game.
require_once ROOT.'/app/Libs/Helpers.php';
require_once ROOT.'/app/Libs/Database.php';
require_once ROOT.'/app/Libs/Validation.php';

require_once ROOT.'/app/Models/User.php';
require_once ROOT.'/app/Models/Item.php';
require_once ROOT.'/app/Models/Drop.php';

// We'll build our config array by grabbing the contents of our config files.
$config = [
    'game' => require_once ROOT.'/app/Config/Game.php',
    'auth' => require_once ROOT.'/app/Config/Auth.php',
    'classes' => require_once ROOT.'/app/Config/Classes.php',
];

// We'll spin up or resume a session on the server.
session_start();

// These variables are what I could define as "metadata", just some things that let us
// make life a little easier and/or nicer.
$start = microtime(true);
$queries = 0;
$version = config('game.general.version');
$build = config('game.general.build');
$link = openLink();
$db = new Database(config('game.db'));
// $control = getControl($link);