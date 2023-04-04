<?php

// Timer for this request.
define('START', microtime(true));

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Pull in all our libraries and load our env vars
require '../bootstrap.php';

$router->get('/', function() {
    return view('index');
});

$router->get('/login', 'Auth::showLogin');
$router->post('/auth/login', 'Auth::doLogin');
$router->get('/register', 'Auth::showRegister');
$router->post('/auth/register', 'Auth::doRegister');

echo $router->run();