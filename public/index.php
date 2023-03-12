<?php

// Timer for this request.
define('START', microtime(true));

// Pull in all our libraries and load our env vars
require '../bootstrap.php';

$router = new Router();
//$DB = new Database();

$router->get('', function() {
    return env('test');
});

echo $router->run();