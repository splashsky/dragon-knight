<?php

require './bootstrap.php';
require './tools/router.php';

Router::get('/', function() {
    echo 'root';
});

Router::get('/login', function() {
    require './pages/login.html';
});

Router::post('/login', function() {
    echo $_POST['username'];
});

Router::run();